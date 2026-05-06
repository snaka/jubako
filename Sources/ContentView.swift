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

    enum Phase { case idle, scanning, done }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            if let ts = snapshotTimestamp, phase == .done { snapshotBanner(ts) }
            if errorCount > 0 { errorBanner }
            if !deferredPaths.isEmpty { deferredBanner }
            if phase == .done {
                Divider()
                breadcrumbBar
            }
            Divider()
            list
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            if !hasLoadedSnapshot {
                hasLoadedSnapshot = true
                loadSnapshotIfAvailable()
            }
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                if phase == .scanning {
                    scanTask?.cancel()
                } else {
                    scanTask = Task { await runScan(roots: [NSHomeDirectory()], merge: false) }
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
        case .scanning: return "Scanning… \(liveFiles.formatted()) files · \(byteString(liveBytes))"
        case .done: return "Done"
        }
    }

    // MARK: - Banners

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
                scanTask = Task { await runScan(roots: [NSHomeDirectory()], merge: false) }
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
                scanTask = Task { await runScan(roots: toRetry, merge: true) }
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
        Group {
            if phase == .done && entriesAtCurrent.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No entries here")
                        .foregroundStyle(.secondary)
                    Text("This folder may have been skipped due to permissions, or contains only items below the display threshold.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entriesAtCurrent) { entry in
                    Button {
                        if entry.isDirectory {
                            navigate(to: entry.path)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                                .foregroundStyle(entry.isDirectory ? .blue : .gray)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text((entry.path as NSString).lastPathComponent)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(entry.modifiedAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(byteString(entry.size))
                                .font(.system(.body, design: .monospaced))
                            if entry.isDirectory {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Navigation

    private func navigate(to path: String) {
        currentPath = path
    }

    // MARK: - Scan

    @MainActor
    private func runScan(roots: [String], merge: Bool) async {
        phase = .scanning
        if !merge {
            liveFiles = 0
            liveBytes = 0
            errorCount = 0
            lastError = ""
            deferredPaths = []
            byParent = [:]
            elapsed = 0
            rootPath = roots.first ?? NSHomeDirectory()
            currentPath = rootPath
        } else {
            deferredPaths = []
        }

        let baseSnapshot = byParent
        let isRetry = merge
        let primaryRoot = roots.first ?? NSHomeDirectory()
        let homeRoot = rootPath

        await Task.detached(priority: .userInitiated) {
            var localByParent = baseSnapshot

            let prefixes = isRetry
                ? DiskScanner.defaultSkipPathPrefixes
                : DiskScanner.defaultSkipPathPrefixesForHome(primaryRoot)
            let options = ScanOptions(skipPathPrefixes: prefixes)
            let scanner = DiskScanner()

            for await event in scanner.scan(roots: roots, options: options) {
                switch event {
                case .progress(let n, let b, _):
                    if !isRetry {
                        await MainActor.run {
                            liveFiles = n
                            liveBytes = b
                        }
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
                    let snapshotData = (
                        rootPath: homeRoot,
                        byParent: synthesized,
                        totalFiles: isRetry ? (await MainActor.run { liveFiles } + n) : n,
                        totalBytes: isRetry ? (await MainActor.run { liveBytes } + b) : b,
                        elapsed: isRetry ? (await MainActor.run { elapsed } + d) : d
                    )
                    await MainActor.run {
                        if isRetry {
                            liveFiles += n
                            liveBytes += b
                            elapsed += d
                        } else {
                            liveFiles = n
                            liveBytes = b
                            elapsed = d
                        }
                        byParent = synthesized
                        snapshotTimestamp = Date()
                        phase = .done
                    }
                    let captured = await MainActor.run { (
                        errorCount: errorCount,
                        lastError: lastError,
                        deferredPaths: deferredPaths
                    ) }
                    Task.detached(priority: .background) {
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
                    }
                }
            }
        }.value
        scanTask = nil
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
private func synthesizeShallowDirs(
    byParent: [String: [ScanEntry]],
    rootPath: String
) -> [String: [ScanEntry]] {
    var result = byParent
    var toSynthesize: [String] = []

    for dir in result.keys {
        if dir == rootPath { continue }
        if dir.isEmpty || dir == "/" { continue }
        if !dir.hasPrefix(rootPath + "/") { continue }
        let grandparent = (dir as NSString).deletingLastPathComponent
        if grandparent.isEmpty || grandparent == "/" { continue }
        let listed = result[grandparent]?.contains(where: { $0.path == dir }) ?? false
        if !listed {
            toSynthesize.append(dir)
        }
    }

    toSynthesize.sort { a, b in
        a.split(separator: "/").count > b.split(separator: "/").count
    }

    for path in toSynthesize {
        let children = result[path] ?? []
        let total = children.reduce(0) { $0 + $1.size }
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
