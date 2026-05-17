import SwiftUI
import AppKit

/// Compact pill that names the macOS app owning the surrounding folder,
/// optionally with the app's Dock icon. Rendered next to the size figure
/// on BentoCards and in the row layout for items past the top 12.
struct AppPill: View {
    let info: AppInfo

    var body: some View {
        HStack(spacing: 4) {
            if let icon = AppResolver.shared.icon(for: info) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 12, height: 12)
            }
            Text(info.displayName)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Color.secondary.opacity(0.12))
        )
    }
}
