import SwiftUI

/// Three-segment volume capacity bar: bytes that Jubako has scanned, bytes
/// otherwise in use on the same volume, and free bytes. Renders a thin bar
/// with a one-line legend underneath.
struct DiskUsageBar: View {
    let volume: VolumeUsage
    let scannedBytes: Int64

    private var clampedScanned: Int64 {
        // The scanned figure can exceed (total - free) on a typical Mac because
        // APFS hard links, clone files, snapshots, and double-counted sibling
        // paths inflate Jubako's on-disk byte sum. Cap at the used region so
        // the bar stays sensible.
        min(max(0, scannedBytes), volume.usedBytes)
    }

    private var otherBytes: Int64 {
        max(0, volume.usedBytes - clampedScanned)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            bar
            HStack(spacing: 12) {
                legend(color: .orange, label: "Scanned", bytes: clampedScanned)
                legend(color: .secondary, label: "Other", bytes: otherBytes)
                legend(color: .green, label: "Free", bytes: volume.availableBytes)
                Spacer()
                Text("\(volume.volumeName) · \(byteString(volume.totalBytes)) total")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var bar: some View {
        GeometryReader { geo in
            let total = max(1, volume.totalBytes)
            let scannedW = geo.size.width * CGFloat(clampedScanned) / CGFloat(total)
            let otherW = geo.size.width * CGFloat(otherBytes) / CGFloat(total)
            let freeW = max(0, geo.size.width - scannedW - otherW)
            HStack(spacing: 0) {
                Rectangle().fill(Color.orange).frame(width: scannedW)
                Rectangle().fill(Color.secondary.opacity(0.55)).frame(width: otherW)
                Rectangle().fill(Color.green.opacity(0.75)).frame(width: freeW)
            }
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
            )
        }
        .frame(height: 8)
    }

    private func legend(color: Color, label: String, bytes: Int64) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(label) \(byteString(bytes))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func byteString(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
