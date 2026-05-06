import SwiftUI

struct ContentView: View {
    @State private var phase: Phase = .idle
    @State private var liveFiles: Int = 0
    @State private var liveBytes: Int64 = 0
    @State private var errorCount: Int = 0
    @State private var lastError: String = ""
    @State private var topFiles: [ScanEntry] = []
    @State private var elapsed: TimeInterval = 0
    @State private var scanTask: Task<Void, Never>?

    enum Phase { case idle, scanning, done }

    var body: some View {
        VStack(spacing: 0) {
            header
            if errorCount > 0 { errorBanner }
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
                    scanTask = Task { await runScan(root: NSHomeDirectory()) }
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
    private func runScan(root: String) async {
        phase = .scanning
        liveFiles = 0
        liveBytes = 0
        errorCount = 0
        lastError = ""
        topFiles = []
        elapsed = 0

        // Run the event consumption loop off the main actor; only hop back
        // to MainActor on rare events (progress / error / finished).
        await Task.detached(priority: .userInitiated) {
            var collected: [ScanEntry] = []
            collected.reserveCapacity(50_000)

            let options = ScanOptions(
                skipPathPrefixes: DiskScanner.defaultSkipPathPrefixesForHome(root)
            )
            let scanner = DiskScanner()
            for await event in scanner.scan(root: root, options: options) {
                switch event {
                case .progress(let n, let b, _):
                    await MainActor.run {
                        liveFiles = n
                        liveBytes = b
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
                case .finished(let n, let b, let d):
                    let top = Array(collected.sorted { $0.size > $1.size }.prefix(100))
                    await MainActor.run {
                        liveFiles = n
                        liveBytes = b
                        elapsed = d
                        topFiles = top
                        phase = .done
                    }
                }
            }
        }.value
        scanTask = nil
    }

    private func byteString(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

#Preview {
    ContentView()
}
