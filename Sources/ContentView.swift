import SwiftUI

struct ContentView: View {
    @State private var phase: Phase = .idle
    @State private var liveFiles: Int = 0
    @State private var liveBytes: Int64 = 0
    @State private var errorCount: Int = 0
    @State private var lastError: String = ""
    @State private var deferredPaths: [String] = []
    @State private var elapsed: TimeInterval = 0
    @State private var rootPath: String = NSHomeDirectory()
    @State private var currentPath: String = NSHomeDirectory()
    @State private var byParent: [String: [ScanEntry]] = [:]
    @State private var scanTask: Task<Void, Never>?
    @State private var snapshotTimestamp: Date?
    @State private var hasLoadedSnapshot: Bool = false
    @State private var isSaving: Bool = false
    @State private var showOnboarding: Bool = false

    enum Phase { case idle, scanning, done }

    enum ScanMode {
        case fullScan(root: String)
        case deferredRetry(roots: [String])
        case subtreeReplace(target: String)
    }

    @State private var scanningLabel: String = ""

    var body: some View {
        Group {
            if showOnboarding {
                OnboardingView(
                    onContinueWithout: { showOnboarding = false },
                    onRecheck: { showOnboarding = false }
                )
            } else {
                mainContent
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            if !hasLoadedSnapshot {
                hasLoadedSnapshot = true
                loadSnapshotIfAvailable()
                // First-launch onboarding only fires when the user has no
                // prior snapshot AND macOS reports we don't have Full Disk
                // Access. Returning users see the regular UI plus the
                // existing deferred banner.
                if phase == .idle && !FDAProbe.hasAccess() {
                    showOnboarding = true
                }
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            controlBar
            if isSaving { savingBanner }
            if let ts = snapshotTimestamp, phase == .done, !isSaving { snapshotBanner(ts) }
            if errorCount > 0 { errorBanner }
            if !deferredPaths.isEmpty { deferredBanner }
            if phase == .done {
                Divider()
                breadcrumbBar
            }
            Divider()
            list
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                if phase == .scanning {
                    scanTask?.cancel()
                } else {
                    scanTask = Task { await runScan(mode: .fullScan(root: NSHomeDirectory())) }
                }
            } label: {
                Text(phase == .scanning ? "Cancel" : "Scan Home")
                    .frame(minWidth: 90)
            }
            .keyboardShortcut(.defaultAction)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusLine)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if phase == .done {
                    Text("\(liveFiles.formatted()) files · \(byteString(liveBytes)) total · \(String(format: "%.2fs", elapsed))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
    }

    private var statusLine: String {
        switch phase {
        case .idle: return "Idle"
        case .scanning:
            let label = scanningLabel.isEmpty ? "Scanning…" : "\(scanningLabel)…"
            return "\(label) \(liveFiles.formatted()) files · \(byteString(liveBytes))"
        case .done: return "Done"
        }
    }

    // MARK: - Banners

    private var savingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Saving snapshot… (don't quit until this finishes)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
    }

    private func snapshotBanner(_ ts: Date) -> some View {
        let age = Date().timeIntervalSince(ts)
        let isStale = age > 60 * 60 * 24 * 7  // 7 days
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: ts, relativeTo: Date())
        return HStack(spacing: 8) {
            Image(systemName: isStale ? "clock.badge.exclamationmark.fill" : "clock")
                .foregroundStyle(isStale ? .orange : .secondary)
            Text(isStale
                ? "Snapshot from \(relative) — likely stale, consider rescanning."
                : "Snapshot from \(relative).")
                .font(.caption)
            Spacer()
            Button("Rescan") {
                scanTask = Task { await runScan(mode: .fullScan(root: NSHomeDirectory())) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(phase == .scanning)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background((isStale ? Color.orange : Color.secondary).opacity(0.08))
    }

    private var errorBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("\(errorCount) errors (latest: \(lastError))")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
    }

    private var deferredBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.blue)
            Text("\(deferredPaths.count) folders skipped (permissions). Grant Full Disk Access to include them.")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Open Privacy Settings") { openFullDiskAccessSettings() }
                .buttonStyle(.borderless)
                .font(.caption)
            Button {
                let toRetry = deferredPaths
                scanTask = Task { await runScan(mode: .deferredRetry(roots: toRetry)) }
            } label: {
                Text("Retry").frame(minWidth: 60)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(phase == .scanning)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.08))
    }

    // MARK: - Breadcrumb

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            Button {
                let parent = (currentPath as NSString).deletingLastPathComponent
                if currentPath != rootPath, parent.hasPrefix(rootPath) || parent == rootPath {
                    navigate(to: parent)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(currentPath == rootPath)

            ForEach(Array(breadcrumbComponents().enumerated()), id: \.offset) { idx, pair in
                let (label, path) = pair
                if idx > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button(action: { navigate(to: path) }) {
                    Text(label)
                        .font(.callout)
                        .foregroundStyle(path == currentPath ? Color.primary : Color.accentColor)
                        .fontWeight(path == currentPath ? .semibold : .regular)
                }
                .buttonStyle(.plain)
                .disabled(path == currentPath)
            }

            Spacer()

            if phase == .scanning {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                    Text("\(liveFiles.formatted()) files · \(byteString(liveBytes))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .help(scanningLabel.isEmpty ? "Scanning…" : "\(scanningLabel)…")
            } else {
                Button {
                    guard scanTask == nil, byParent[currentPath] != nil else { return }
                    let target = currentPath
                    scanTask = Task { await runScan(mode: .subtreeReplace(target: target)) }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(byParent[currentPath] == nil)
                .help("Rescan this folder")
            }

            Text(byteString(currentTotalSize))
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func breadcrumbComponents() -> [(String, String)] {
        guard currentPath.hasPrefix(rootPath) else { return [] }
        let rootLabel = (rootPath as NSString).lastPathComponent.isEmpty ? "/" : (rootPath as NSString).lastPathComponent
        var pairs: [(String, String)] = [(rootLabel, rootPath)]
        let suffix = String(currentPath.dropFirst(rootPath.count))
        var current = rootPath
        for component in suffix.split(separator: "/").map(String.init) {
            current += "/" + component
            pairs.append((component, current))
        }
        return pairs
    }

    private var currentTotalSize: Int64 {
        (byParent[currentPath] ?? []).reduce(0) { $0 + $1.size }
    }

    private var entriesAtCurrent: [ScanEntry] {
        guard let list = byParent[currentPath] else { return [] }
        return Array(list.sorted { $0.size > $1.size }.prefix(200))
    }

    // MARK: - List

    private var list: some View {
        BentoGridView(entries: entriesAtCurrent) { entry in
            navigate(to: entry.path)
        }
    }

    // MARK: - Navigation

    private func navigate(to path: String) {
        currentPath = path
    }

    // MARK: - Scan

    @MainActor
    private func runScan(mode: ScanMode) async {
        phase = .scanning

        let roots: [String]
        let isAccumulate: Bool         // add to existing totals (deferredRetry/subtreeReplace) vs. replace (fullScan)
        let elapsedAccumulate: Bool    // add to elapsed vs. overwrite
        let pruneStats: (files: Int, bytes: Int64)

        switch mode {
        case .fullScan(let root):
            roots = [root]
            isAccumulate = false
            elapsedAccumulate = false
            pruneStats = (0, 0)
            liveFiles = 0
            liveBytes = 0
            errorCount = 0
            lastError = ""
            deferredPaths = []
            byParent = [:]
            elapsed = 0
            rootPath = root
            currentPath = root
            scanningLabel = "Scanning"
        case .deferredRetry(let retryRoots):
            roots = retryRoots
            isAccumulate = true
            elapsedAccumulate = true
            pruneStats = (0, 0)
            deferredPaths = []
            scanningLabel = "Retrying"
        case .subtreeReplace(let target):
            roots = [target]
            isAccumulate = true
            elapsedAccumulate = false
            // Drop old entries and deferred paths under the target before re-scanning.
            let removed = pruneSubtreeFromByParent(root: target)
            pruneStats = removed
            liveFiles = max(0, liveFiles - removed.files)
            liveBytes = max(0, liveBytes - removed.bytes)
            let prefix = target + "/"
            deferredPaths.removeAll { $0 == target || $0.hasPrefix(prefix) }
            let basename = (target as NSString).lastPathComponent
            scanningLabel = "Rescanning \(basename)"
        }
        _ = pruneStats

        let baseSnapshot = byParent
        let primaryRoot = roots.first ?? NSHomeDirectory()
        let homeRoot = rootPath
        let scanRoots = roots
        let accumulate = isAccumulate
        let bumpElapsed = elapsedAccumulate
        // .progress events only carry counts for the current scan, so the UI
        // adds them to the pre-scan baseline (i.e. the prune-adjusted totals).
        let baseFiles = liveFiles
        let baseBytes = liveBytes

        await Task.detached(priority: .userInitiated) {
            var localByParent = baseSnapshot

            // Build the TCC-protected skip list against the user's home. For a
            // subtreeReplace target outside the home, the base prefixes alone
            // are still the safer choice.
            let prefixes = DiskScanner.defaultSkipPathPrefixesForHome(homeRoot)
            // Keep workerCount at the default (2). Empirically 2 is the sweet
            // spot for a full home scan (~700 GB / 6.5M files in ~3 min on
            // Apple Silicon); raising it backs up the AsyncStream consumer on
            // .file/.directory events and the main actor starts getting flagged
            // as "Not Responding".
            let options = ScanOptions(skipPathPrefixes: prefixes)
            let scanner = DiskScanner()

            for await event in scanner.scan(roots: scanRoots, options: options) {
                switch event {
                case .progress(let n, let b, _):
                    await MainActor.run {
                        liveFiles = baseFiles + n
                        liveBytes = baseBytes + b
                    }
                case .file(let f):
                    let parent = (f.path as NSString).deletingLastPathComponent
                    localByParent[parent, default: []].append(f)
                case .directory(let d):
                    let parent = (d.path as NSString).deletingLastPathComponent
                    localByParent[parent, default: []].append(d)
                case .error(let p, let m):
                    await MainActor.run {
                        errorCount += 1
                        lastError = "\(p): \(m)"
                    }
                case .deferred(let p, _):
                    await MainActor.run {
                        deferredPaths.append(p)
                    }
                case .finished(let n, let b, let d):
                    let synthesized = synthesizeShallowDirs(byParent: localByParent, rootPath: homeRoot)
                    // accumulate adds the new counts to the baseline (carried
                    // over from the old snapshot). For fullScan baseFiles and
                    // baseBytes are both 0, so the same expression works.
                    let totalFiles = accumulate ? (baseFiles + n) : n
                    let totalBytes = accumulate ? (baseBytes + b) : b
                    let totalElapsed: TimeInterval
                    if accumulate && bumpElapsed {
                        totalElapsed = await MainActor.run { elapsed } + d
                    } else {
                        totalElapsed = d
                    }
                    let snapshotData = (
                        rootPath: homeRoot,
                        byParent: synthesized,
                        totalFiles: totalFiles,
                        totalBytes: totalBytes,
                        elapsed: totalElapsed
                    )
                    await MainActor.run {
                        liveFiles = totalFiles
                        liveBytes = totalBytes
                        elapsed = totalElapsed
                        byParent = synthesized
                        snapshotTimestamp = Date()
                        scanningLabel = ""
                        phase = .done
                    }
                    let captured = await MainActor.run { () -> (errorCount: Int, lastError: String, deferredPaths: [String]) in
                        isSaving = true
                        return (errorCount, lastError, deferredPaths)
                    }
                    Task.detached(priority: .userInitiated) {
                        let snap = ScanSnapshot(
                            scannedAt: Date(),
                            rootPath: snapshotData.rootPath,
                            totalFiles: snapshotData.totalFiles,
                            totalBytes: snapshotData.totalBytes,
                            elapsed: snapshotData.elapsed,
                            errorCount: captured.errorCount,
                            lastError: captured.lastError,
                            deferredPaths: captured.deferredPaths,
                            entriesByParent: SnapshotStore.prune(snapshotData.byParent)
                        )
                        SnapshotStore.save(snap)
                        await MainActor.run { isSaving = false }
                    }
                }
            }
        }.value
        _ = primaryRoot
        scanTask = nil
    }

    /// Removes everything under `root` from byParent and returns the
    /// (files, bytes) that were dropped. The parent list also has the root's
    /// own entry removed so the scanner's new `.directory` emit for the same
    /// path doesn't produce a duplicate.
    ///
    /// IMPORTANT: do all mutation on a local copy, then assign the dict back
    /// to @State exactly once. The @State setter fires a SwiftUI transaction
    /// on every call, which CoW-copies and deinits the whole Dictionary;
    /// calling `byParent.removeValue` in a loop is O(N×K) retain/release and
    /// froze the main thread for minutes on a home-sized snapshot (confirmed
    /// via `sample`).
    private func pruneSubtreeFromByParent(root: String) -> (files: Int, bytes: Int64) {
        let prefix = root + "/"
        var removedFiles = 0
        var removedBytes: Int64 = 0
        var local = byParent
        let keysToRemove = local.keys.filter { $0 == root || $0.hasPrefix(prefix) }
        for key in keysToRemove {
            for e in local[key] ?? [] where !e.isDirectory {
                removedFiles += 1
                removedBytes += e.size
            }
            local.removeValue(forKey: key)
        }
        let parent = (root as NSString).deletingLastPathComponent
        local[parent]?.removeAll { $0.path == root }
        byParent = local
        return (removedFiles, removedBytes)
    }

    // MARK: - Helpers

    private func loadSnapshotIfAvailable() {
        guard let snap = SnapshotStore.load() else { return }
        rootPath = snap.rootPath
        currentPath = snap.rootPath
        byParent = snap.entriesByParent
        liveFiles = snap.totalFiles
        liveBytes = snap.totalBytes
        elapsed = snap.elapsed
        errorCount = snap.errorCount
        lastError = snap.lastError
        deferredPaths = snap.deferredPaths
        snapshotTimestamp = snap.scannedAt
        phase = .done
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func byteString(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

/// Adds synthetic directory entries for shallow dirs (those above seedDepth)
/// that the scanner doesn't emit `.directory` events for. Each synth's size is
/// the sum of its known children, processed deepest-first so parent sums
/// pick up child synths.
///
/// Performance: pre-computes a Set<String> of dir paths per parent so the
/// "is this dir already listed under its grandparent?" check is O(1).
/// Without that, the check is O(M) per dir × O(N) dirs = O(N²/avg_M).
private func synthesizeShallowDirs(
    byParent: [String: [ScanEntry]],
    rootPath: String
) -> [String: [ScanEntry]] {
    var result = byParent

    // For each parent, collect the set of dir-paths that are listed there.
    var dirsListedIn: [String: Set<String>] = [:]
    dirsListedIn.reserveCapacity(result.count)
    for (parent, entries) in result {
        var set = Set<String>()
        for e in entries where e.isDirectory {
            set.insert(e.path)
        }
        if !set.isEmpty {
            dirsListedIn[parent] = set
        }
    }

    let rootPrefix = rootPath + "/"
    var toSynthesize: [String] = []
    toSynthesize.reserveCapacity(64)

    for dir in result.keys {
        if dir == rootPath { continue }
        if dir.isEmpty || dir == "/" { continue }
        if !dir.hasPrefix(rootPrefix) { continue }
        let grandparent = (dir as NSString).deletingLastPathComponent
        if grandparent.isEmpty || grandparent == "/" { continue }
        if dirsListedIn[grandparent]?.contains(dir) == true { continue }
        toSynthesize.append(dir)
    }

    // Deepest first so a parent's synth picks up its children's synths.
    toSynthesize.sort { lhs, rhs in
        lhs.utf8.lazy.filter { $0 == UInt8(ascii: "/") }.count
            > rhs.utf8.lazy.filter { $0 == UInt8(ascii: "/") }.count
    }

    for path in toSynthesize {
        let children = result[path] ?? []
        var total: Int64 = 0
        for c in children { total += c.size }
        let entry = ScanEntry(
            path: path,
            size: total,
            isDirectory: true,
            modifiedAt: Date.distantPast,
            accessedAt: Date.distantPast
        )
        let grandparent = (path as NSString).deletingLastPathComponent
        result[grandparent, default: []].append(entry)
    }

    return result
}

#Preview {
    ContentView()
}
