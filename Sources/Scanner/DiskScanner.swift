import Foundation
import Darwin

public struct ScanEntry: Sendable, Hashable, Identifiable, Codable {
    public var id: String { path }
    public let path: String
    public let size: Int64
    public let isDirectory: Bool
    public let modifiedAt: Date
    public let accessedAt: Date

    private enum CodingKeys: String, CodingKey {
        case path, size, isDirectory, modifiedAt, accessedAt
    }
}

public enum ScanEvent: Sendable {
    case progress(filesSeen: Int, bytesSeen: Int64, currentPath: String)
    case file(ScanEntry)
    case directory(ScanEntry)
    case error(path: String, message: String)
    /// Permission-denied paths that the user can retry after granting Full Disk Access.
    case deferred(path: String, reason: String)
    case finished(filesSeen: Int, bytesSeen: Int64, duration: TimeInterval)
}

public struct ScanOptions: Sendable {
    public var skipPathPrefixes: [String]
    public var skipBasenames: Set<String>
    public var progressEveryFiles: Int
    /// How many directory levels to enumerate sequentially before handing
    /// subtrees off to workers. Higher values give better load balance at the
    /// cost of an upfront serial walk. 2 is a good default for a home dir.
    public var seedDepth: Int
    /// Number of concurrent worker tasks performing fts walks.
    public var workerCount: Int

    public init(
        skipPathPrefixes: [String] = DiskScanner.defaultSkipPathPrefixes,
        skipBasenames: Set<String> = DiskScanner.defaultSkipBasenames,
        progressEveryFiles: Int = 500,
        seedDepth: Int = 2,
        workerCount: Int = 2
    ) {
        self.skipPathPrefixes = skipPathPrefixes
        self.skipBasenames = skipBasenames
        self.progressEveryFiles = progressEveryFiles
        self.seedDepth = seedDepth
        self.workerCount = workerCount
    }
}

public final class DiskScanner: @unchecked Sendable {
    public static let defaultSkipPathPrefixes: [String] = [
        "/System",
        "/private/var/vm",
        "/private/var/db/dyld",
        "/Volumes",
        "/dev",
        "/.vol",
    ]

    public static let defaultSkipBasenames: Set<String> = [
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd",
        ".DocumentRevisions-V100",
        ".TemporaryItems",
    ]

    /// User-Library subpaths that are TCC-protected and will silently EPERM
    /// without Full Disk Access. We pre-skip them to avoid an error flood and
    /// emit `.deferred` events for them so the UI can prompt for FDA + retry.
    public static let tccProtectedHomeSubpaths: [String] = [
        "Library/Mail",
        "Library/Messages",
        "Library/Safari",
        "Library/Cookies",
        "Library/HomeKit",
        "Library/Suggestions",
        "Library/Calendars",
        "Library/Reminders",
        "Library/Shortcuts",
        "Library/IdentityServices",
        "Library/Containers",
        "Library/Group Containers",
        "Library/Application Support/CallHistoryDB",
        "Library/Application Support/CallHistoryTransactions",
        "Library/Application Support/com.apple.TCC",
        "Library/Application Support/AddressBook",
        "Library/PersonalizationPortrait",
    ]

    public static func defaultSkipPathPrefixesForHome(_ home: String) -> [String] {
        defaultSkipPathPrefixes + tccProtectedHomeSubpaths.map { home + "/" + $0 }
    }

    public init() {}

    public func scan(root: String, options: ScanOptions = ScanOptions()) -> AsyncStream<ScanEvent> {
        scan(roots: [root], options: options)
    }

    /// Multi-root variant. Useful for retrying a list of previously-deferred paths.
    public func scan(roots: [String], options: ScanOptions = ScanOptions()) -> AsyncStream<ScanEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task.detached(priority: .userInitiated) { [self] in
                await run(roots: roots, options: options, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        roots: [String],
        options: ScanOptions,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        let started = Date()
        let controller = ScanController(progressEveryFiles: options.progressEveryFiles)

        // Pre-walk: emit files at shallow depth, queue subtrees at depth >= seedDepth
        for root in roots {
            await preWalk(
                root,
                depth: 0,
                maxDepth: options.seedDepth,
                options: options,
                controller: controller,
                continuation: continuation
            )
        }
        await controller.markSeedingComplete()

        // Spawn workers
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<max(1, options.workerCount) {
                group.addTask { [self] in
                    await workerLoop(
                        controller: controller,
                        continuation: continuation,
                        options: options
                    )
                }
            }
        }

        let duration = Date().timeIntervalSince(started)
        let totals = await controller.totals()
        continuation.yield(.finished(
            filesSeen: totals.files,
            bytesSeen: totals.bytes,
            duration: duration
        ))
    }

    /// Walks the tree synchronously up to `maxDepth`, emitting files inline and
    /// pushing subtrees at depth==maxDepth onto the controller's queue.
    private func preWalk(
        _ path: String,
        depth: Int,
        maxDepth: Int,
        options: ScanOptions,
        controller: ScanController,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        if Task.isCancelled { return }
        let basename = (path as NSString).lastPathComponent
        if shouldSkip(path: path, basename: basename, options: options) { return }

        if depth >= maxDepth {
            await controller.enqueueSubtree(path)
            return
        }

        // List children
        let children: [String]
        do {
            children = try FileManager.default.contentsOfDirectory(atPath: path)
        } catch let err as NSError {
            if Self.isPermissionError(err) {
                continuation.yield(.deferred(path: path, reason: err.localizedDescription))
            } else {
                continuation.yield(.error(path: path, message: err.localizedDescription))
            }
            return
        }

        for name in children {
            let full = path + "/" + name
            if shouldSkip(path: full, basename: name, options: options) { continue }

            var st = stat()
            if lstat(full, &st) != 0 { continue }

            if (st.st_mode & S_IFMT) == S_IFDIR {
                await preWalk(
                    full,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    options: options,
                    controller: controller,
                    continuation: continuation
                )
            } else if (st.st_mode & S_IFMT) == S_IFREG || (st.st_mode & S_IFMT) == S_IFLNK {
                let entry = ScanEntry(
                    path: full,
                    size: Int64(st.st_blocks) * 512,
                    isDirectory: false,
                    modifiedAt: st.modificationDate,
                    accessedAt: st.accessDate
                )
                continuation.yield(.file(entry))
                await controller.recordFile(size: entry.size, currentPath: full, continuation: continuation)
            }
        }
    }

    private func workerLoop(
        controller: ScanController,
        continuation: AsyncStream<ScanEvent>.Continuation,
        options: ScanOptions
    ) async {
        while !Task.isCancelled {
            guard let subtree = await controller.nextWork() else { break }
            await scanSubtree(
                subtree,
                options: options,
                controller: controller,
                continuation: continuation
            )
            await controller.workItemCompleted()
        }
    }

    private func scanSubtree(
        _ root: String,
        options: ScanOptions,
        controller: ScanController,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        let argv = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 2)
        argv[0] = strdup(root)
        argv[1] = nil
        defer {
            if let p = argv[0] { free(p) }
            argv.deallocate()
        }

        guard let handle = fts_open(argv, FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
            let err = String(cString: strerror(errno))
            continuation.yield(.error(path: root, message: "fts_open: \(err)"))
            return
        }
        defer { fts_close(handle) }

        var dirStack: [(path: String, size: Int64)] = []
        var localFiles = 0
        var localBytes: Int64 = 0
        var lastFlushPath = root
        let flushEvery = 500

        while !Task.isCancelled {
            errno = 0
            guard let entryPtr = fts_read(handle) else {
                if errno != 0 {
                    let err = String(cString: strerror(errno))
                    continuation.yield(.error(path: root, message: "fts_read: \(err)"))
                }
                break
            }
            let info = entryPtr.pointee
            let path = String(cString: info.fts_path)
            let basename = (path as NSString).lastPathComponent
            let kind = Int32(info.fts_info)

            switch kind {
            case FTS_D:
                if shouldSkip(path: path, basename: basename, options: options) {
                    fts_set(handle, entryPtr, FTS_SKIP)
                    continue
                }
                dirStack.append((path: path, size: 0))

            case FTS_DP:
                let acc = dirStack.popLast() ?? (path: path, size: 0)
                if let st = info.fts_statp?.pointee {
                    let entry = ScanEntry(
                        path: acc.path,
                        size: acc.size,
                        isDirectory: true,
                        modifiedAt: st.modificationDate,
                        accessedAt: st.accessDate
                    )
                    continuation.yield(.directory(entry))
                }
                if !dirStack.isEmpty {
                    dirStack[dirStack.count - 1].size += acc.size
                }

            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let st = info.fts_statp?.pointee else { continue }
                let onDisk = Int64(st.st_blocks) * 512
                let entry = ScanEntry(
                    path: path,
                    size: onDisk,
                    isDirectory: false,
                    modifiedAt: st.modificationDate,
                    accessedAt: st.accessDate
                )
                continuation.yield(.file(entry))
                localFiles += 1
                localBytes += onDisk
                lastFlushPath = path
                if !dirStack.isEmpty {
                    dirStack[dirStack.count - 1].size += onDisk
                }
                if localFiles >= flushEvery {
                    let result = await controller.recordBatch(files: localFiles, bytes: localBytes)
                    if result.shouldEmitProgress {
                        continuation.yield(.progress(
                            filesSeen: result.totalFiles,
                            bytesSeen: result.totalBytes,
                            currentPath: lastFlushPath
                        ))
                    }
                    localFiles = 0
                    localBytes = 0
                }

            case FTS_DNR, FTS_NS, FTS_ERR:
                let code = info.fts_errno
                let msg = String(cString: strerror(code))
                if code == EPERM || code == EACCES {
                    continuation.yield(.deferred(path: path, reason: msg))
                } else {
                    continuation.yield(.error(path: path, message: msg))
                }

            default:
                break
            }
        }

        // Final flush of any unreported files
        if localFiles > 0 || localBytes > 0 {
            let result = await controller.recordBatch(files: localFiles, bytes: localBytes)
            if result.shouldEmitProgress {
                continuation.yield(.progress(
                    filesSeen: result.totalFiles,
                    bytesSeen: result.totalBytes,
                    currentPath: lastFlushPath
                ))
            }
        }
    }

    private func shouldSkip(path: String, basename: String, options: ScanOptions) -> Bool {
        if options.skipBasenames.contains(basename) { return true }
        for prefix in options.skipPathPrefixes where path == prefix || path.hasPrefix(prefix + "/") {
            return true
        }
        return false
    }

    private static func isPermissionError(_ err: NSError) -> Bool {
        if err.domain == NSCocoaErrorDomain && err.code == NSFileReadNoPermissionError {
            return true
        }
        if err.domain == NSPOSIXErrorDomain {
            let c = Int32(err.code)
            return c == EPERM || c == EACCES
        }
        return false
    }
}

// MARK: - ScanController

private actor ScanController {
    private var pending: [String] = []
    private var inFlight: Int = 0
    private var seedingDone: Bool = false
    private var totalFiles: Int = 0
    private var totalBytes: Int64 = 0
    private var lastProgressFiles: Int = 0
    private var waiters: [CheckedContinuation<String?, Never>] = []
    private let progressEveryFiles: Int

    init(progressEveryFiles: Int) {
        self.progressEveryFiles = progressEveryFiles
    }

    func enqueueSubtree(_ path: String) {
        pending.append(path)
        wakeOneIfPossible()
    }

    func markSeedingComplete() {
        seedingDone = true
        if pending.isEmpty && inFlight == 0 {
            wakeAllWithNil()
        }
    }

    func nextWork() async -> String? {
        if let next = pending.popLast() {
            inFlight += 1
            return next
        }
        if seedingDone && inFlight == 0 {
            return nil
        }
        return await withCheckedContinuation { c in
            waiters.append(c)
        }
    }

    func workItemCompleted() {
        inFlight -= 1
        if seedingDone && pending.isEmpty && inFlight == 0 {
            wakeAllWithNil()
        }
    }

    /// Called by pre-walk for files emitted at shallow depth.
    func recordFile(size: Int64, currentPath: String, continuation: AsyncStream<ScanEvent>.Continuation) {
        totalFiles += 1
        totalBytes += size
        if totalFiles - lastProgressFiles >= progressEveryFiles {
            lastProgressFiles = totalFiles
            continuation.yield(.progress(filesSeen: totalFiles, bytesSeen: totalBytes, currentPath: currentPath))
        }
    }

    /// Called by workers in batches of N files at a time.
    func recordBatch(files: Int, bytes: Int64) -> (totalFiles: Int, totalBytes: Int64, shouldEmitProgress: Bool) {
        totalFiles += files
        totalBytes += bytes
        let shouldEmit = totalFiles - lastProgressFiles >= progressEveryFiles
        if shouldEmit {
            lastProgressFiles = totalFiles
        }
        return (totalFiles, totalBytes, shouldEmit)
    }

    func totals() -> (files: Int, bytes: Int64) {
        (totalFiles, totalBytes)
    }

    private func wakeOneIfPossible() {
        guard !waiters.isEmpty, let next = pending.popLast() else { return }
        let w = waiters.removeFirst()
        inFlight += 1
        w.resume(returning: next)
    }

    private func wakeAllWithNil() {
        let toWake = waiters
        waiters.removeAll()
        for w in toWake { w.resume(returning: nil) }
    }
}

// MARK: - stat helpers

private extension stat {
    var modificationDate: Date {
        Date(timeIntervalSince1970:
            TimeInterval(st_mtimespec.tv_sec)
            + TimeInterval(st_mtimespec.tv_nsec) / 1_000_000_000
        )
    }
    var accessDate: Date {
        Date(timeIntervalSince1970:
            TimeInterval(st_atimespec.tv_sec)
            + TimeInterval(st_atimespec.tv_nsec) / 1_000_000_000
        )
    }
}
