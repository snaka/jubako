import Foundation
import Darwin

public struct ScanEntry: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public let path: String
    public let size: Int64
    public let isDirectory: Bool
    public let modifiedAt: Date
    public let accessedAt: Date
}

public enum ScanEvent: Sendable {
    case progress(filesSeen: Int, bytesSeen: Int64, currentPath: String)
    case file(ScanEntry)
    case directory(ScanEntry)
    case error(path: String, message: String)
    case finished(filesSeen: Int, bytesSeen: Int64, duration: TimeInterval)
}

public struct ScanOptions: Sendable {
    public var skipPathPrefixes: [String]
    public var skipBasenames: Set<String>
    public var progressEveryFiles: Int

    public init(
        skipPathPrefixes: [String] = DiskScanner.defaultSkipPathPrefixes,
        skipBasenames: Set<String> = DiskScanner.defaultSkipBasenames,
        progressEveryFiles: Int = 2000
    ) {
        self.skipPathPrefixes = skipPathPrefixes
        self.skipBasenames = skipBasenames
        self.progressEveryFiles = progressEveryFiles
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

    public init() {}

    public func scan(root: String, options: ScanOptions = ScanOptions()) -> AsyncStream<ScanEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task.detached(priority: .userInitiated) { [self] in
                run(root: root, options: options, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        root: String,
        options: ScanOptions,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) {
        let started = Date()
        var filesSeen = 0
        var bytesSeen: Int64 = 0
        var dirStack: [(path: String, size: Int64)] = []

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
                if let stat = info.fts_statp?.pointee {
                    let entry = ScanEntry(
                        path: acc.path,
                        size: acc.size,
                        isDirectory: true,
                        modifiedAt: stat.modificationDate,
                        accessedAt: stat.accessDate
                    )
                    continuation.yield(.directory(entry))
                }
                if !dirStack.isEmpty {
                    dirStack[dirStack.count - 1].size += acc.size
                }

            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let stat = info.fts_statp?.pointee else { continue }
                let onDisk = Int64(stat.st_blocks) * 512
                let entry = ScanEntry(
                    path: path,
                    size: onDisk,
                    isDirectory: false,
                    modifiedAt: stat.modificationDate,
                    accessedAt: stat.accessDate
                )
                continuation.yield(.file(entry))
                filesSeen += 1
                bytesSeen += onDisk
                if !dirStack.isEmpty {
                    dirStack[dirStack.count - 1].size += onDisk
                }
                if filesSeen % options.progressEveryFiles == 0 {
                    continuation.yield(.progress(filesSeen: filesSeen, bytesSeen: bytesSeen, currentPath: path))
                }

            case FTS_DNR, FTS_ERR, FTS_NS:
                let err = String(cString: strerror(info.fts_errno))
                continuation.yield(.error(path: path, message: err))

            default:
                break
            }
        }

        let duration = Date().timeIntervalSince(started)
        continuation.yield(.finished(filesSeen: filesSeen, bytesSeen: bytesSeen, duration: duration))
    }

    private func shouldSkip(path: String, basename: String, options: ScanOptions) -> Bool {
        if options.skipBasenames.contains(basename) {
            return true
        }
        for prefix in options.skipPathPrefixes where path == prefix || path.hasPrefix(prefix + "/") {
            return true
        }
        return false
    }
}

private extension stat {
    var modificationDate: Date {
        Date(timeIntervalSince1970: TimeInterval(st_mtimespec.tv_sec) + TimeInterval(st_mtimespec.tv_nsec) / 1_000_000_000)
    }
    var accessDate: Date {
        Date(timeIntervalSince1970: TimeInterval(st_atimespec.tv_sec) + TimeInterval(st_atimespec.tv_nsec) / 1_000_000_000)
    }
}

