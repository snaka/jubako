import SwiftUI

struct ContentView: View {
    @State private var phase: Phase = .idle
    @State private var liveFiles: Int = 0
    @State private var liveBytes: Int64 = 0
    @State private var errorCount: Int = 0
    @State private var lastError: String = ""
    @State private var deferredPaths: [String] = []
    @State private var topFiles: [ScanEntry] = []
    @State private var elapsed: TimeInterval = 0
    @State private var scanTask: Task<Void, Never>?
    @State private var collectedSnapshot: [ScanEntry] = []  // accumulator across initial + retry scans

    enum Phase { case idle, scanning, done }

    var body: some View {
        VStack(spacing: 0) {
            header
            if errorCount > 0 { errorBanner }
            if !deferredPaths.isEmpty { deferredBanner }
            Divider()
            list
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private var header: some View {
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
                    Text("\(liveFiles.formatted()) files · \(byteString(liveBytes)) · \(String(format: "%.2fs", elapsed))")
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

    private var list: some View {
        List(topFiles) { entry in
            HStack {
                Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                    .foregroundStyle(entry.isDirectory ? .blue : .gray)
                VStack(alignment: .leading) {
                    Text(entry.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(entry.modifiedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(byteString(entry.size))
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    @MainActor
    private func runScan(roots: [String], merge: Bool) async {
        phase = .scanning
        if !merge {
            liveFiles = 0
            liveBytes = 0
            errorCount = 0
            lastError = ""
            deferredPaths = []
            topFiles = []
            elapsed = 0
            collectedSnapshot = []
        } else {
            // Retry path: clear deferred since we're about to re-attempt those.
            deferredPaths = []
        }

        let baseSnapshot = collectedSnapshot
        let mergedRoots = roots
        let isRetry = merge

        await Task.detached(priority: .userInitiated) {
            var collected: [ScanEntry] = baseSnapshot
            collected.reserveCapacity(max(50_000, baseSnapshot.count + 10_000))

            // Use the home-aware skip prefixes for the primary scan; for retries
            // (which target previously-deferred protected paths) use the base
            // skip list so we don't skip them again.
            let primaryRoot = mergedRoots.first ?? NSHomeDirectory()
            let prefixes = isRetry
                ? DiskScanner.defaultSkipPathPrefixes
                : DiskScanner.defaultSkipPathPrefixesForHome(primaryRoot)
            let options = ScanOptions(skipPathPrefixes: prefixes)
            let scanner = DiskScanner()

            for await event in scanner.scan(roots: mergedRoots, options: options) {
                switch event {
                case .progress(let n, let b, _):
                    await MainActor.run {
                        liveFiles = isRetry ? (liveFiles + n) : n
                        liveBytes = isRetry ? (liveBytes + b) : b
                    }
                case .file(let f):
                    collected.append(f)
                case .directory:
                    break
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
                    let top = Array(collected.sorted { $0.size > $1.size }.prefix(100))
                    let snapshot = collected
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
                        collectedSnapshot = snapshot
                        topFiles = top
                        phase = .done
                    }
                }
            }
        }.value
        scanTask = nil
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

#Preview {
    ContentView()
}
