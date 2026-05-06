import SwiftUI

struct ContentView: View {
    @State private var status: String = "Idle"
    @State private var topFiles: [ScanEntry] = []
    @State private var totalSize: Int64 = 0
    @State private var totalFiles: Int = 0
    @State private var elapsed: TimeInterval = 0
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private var header: some View {
        HStack {
            Button {
                if scanTask == nil {
                    scanTask = Task { await runScan(root: NSHomeDirectory()) }
                } else {
                    scanTask?.cancel()
                }
            } label: {
                Text(scanTask == nil ? "Scan Home" : "Cancel")
                    .frame(minWidth: 90)
            }
            .keyboardShortcut(.defaultAction)

            Text(status)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if totalFiles > 0 {
                Text("\(totalFiles.formatted()) files · \(byteString(totalSize)) · \(String(format: "%.2fs", elapsed))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
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
        status = "Scanning \(root)..."
        topFiles = []
        totalSize = 0
        totalFiles = 0
        elapsed = 0

        var collected: [ScanEntry] = []
        collected.reserveCapacity(10_000)

        let scanner = DiskScanner()
        for await event in scanner.scan(root: root) {
            switch event {
            case .progress(let n, let b, let p):
                status = "Scanning… \(n.formatted()) files · \(byteString(b)) · \(p)"
            case .file(let f):
                collected.append(f)
            case .directory:
                break
            case .error(let p, let m):
                status = "Error at \(p): \(m)"
            case .finished(let n, let b, let d):
                totalFiles = n
                totalSize = b
                elapsed = d
                topFiles = Array(collected.sorted { $0.size > $1.size }.prefix(100))
                status = "Done"
            }
        }
        scanTask = nil
    }

    private func byteString(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

#Preview {
    ContentView()
}
