import SwiftUI

/// Top-of-folder display: a Bento grid of the top 12 entries by size.
/// Anything past index 12 is shown as a compact list below the grid.
struct BentoGridView: View {
    let entries: [ScanEntry]
    let onTap: (ScanEntry) -> Void
    var onRescan: ((ScanEntry) -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if entries.isEmpty {
                    emptyState
                } else {
                    bento
                    if entries.count > 12 {
                        Text("More")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                        VStack(spacing: 2) {
                            ForEach(Array(entries.dropFirst(12).prefix(200))) { e in
                                BentoListRow(entry: e, onTap: onTap, onRescan: onRescan)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var emptyState: some View {
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
        .padding(.vertical, 60)
    }

    @ViewBuilder
    private var bento: some View {
        let top = Array(entries.prefix(12))
        // Hero row: #1 large + (#2, #3, #4) stacked on the right.
        HStack(alignment: .top, spacing: 12) {
            BentoCard(entry: top[0], size: .hero, onTap: onTap, onRescan: onRescan)
                .frame(maxWidth: .infinity)
            VStack(spacing: 12) {
                if top.count > 1 { BentoCard(entry: top[1], size: .secondary, onTap: onTap, onRescan: onRescan) }
                if top.count > 2 { BentoCard(entry: top[2], size: .secondary, onTap: onTap, onRescan: onRescan) }
                if top.count > 3 { BentoCard(entry: top[3], size: .secondary, onTap: onTap, onRescan: onRescan) }
            }
            .frame(width: 240)
        }
        .frame(height: 280)

        // Medium row: #5..#7 (or #5..#8 if we have plenty)
        if top.count > 4 {
            let mediumEnd = min(top.count, 8)
            HStack(spacing: 12) {
                ForEach(4..<mediumEnd, id: \.self) { idx in
                    BentoCard(entry: top[idx], size: .medium, onTap: onTap, onRescan: onRescan)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110)
        }

        // Small row: #9..#12 in a 4-up grid.
        if top.count > 8 {
            let smallStart = 8
            let smallEnd = min(top.count, 12)
            let smallItems = Array(top[smallStart..<smallEnd])
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                spacing: 12
            ) {
                ForEach(smallItems) { item in
                    BentoCard(entry: item, size: .small, onTap: onTap, onRescan: onRescan)
                }
            }
            .frame(minHeight: 90)
        }
    }
}

// MARK: - Card

struct BentoCard: View {
    enum CardSize { case hero, secondary, medium, small }

    let entry: ScanEntry
    let size: CardSize
    let onTap: (ScanEntry) -> Void
    var onRescan: ((ScanEntry) -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        Button {
            if entry.isDirectory { onTap(entry) }
        } label: {
            ZStack(alignment: .topLeading) {
                background
                contents
                    .padding(padding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
            .shadow(color: shadowColor, radius: hovering ? 6 : 2, x: 0, y: hovering ? 4 : 1)
            .scaleEffect(hovering ? 1.015 : 1.0)
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(entry.path)
        .contextMenu {
            if entry.isDirectory, let onRescan {
                Button("Rescan this folder", systemImage: "arrow.clockwise") {
                    onRescan(entry)
                }
            }
        }
    }

    private var background: some View {
        let base = entry.category.tintColor
        return LinearGradient(
            colors: [
                base.opacity(hovering ? 0.22 : 0.14),
                base.opacity(hovering ? 0.10 : 0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        entry.category.tintColor.opacity(0.28)
    }

    private var shadowColor: Color {
        Color.black.opacity(hovering ? 0.10 : 0.05)
    }

    private var contents: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: entry.category.iconName)
                    .font(iconFont)
                    .foregroundStyle(entry.category.tintColor)
                Spacer()
                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 4)
            Text((entry.path as NSString).lastPathComponent)
                .font(nameFont)
                .lineLimit(nameLineLimit)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                Text(byteString)
                    .font(sizeFont)
                    .foregroundStyle(.secondary)
                if showCategoryLabel {
                    Text(entry.category.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(entry.category.tintColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(entry.category.tintColor.opacity(0.15))
                        )
                }
            }
            .padding(.top, 4)
        }
    }

    private var showCategoryLabel: Bool {
        // Hide the label on the smallest cards to keep them readable.
        switch size {
        case .hero, .secondary, .medium: return entry.category != .userFolder && entry.category != .userDocument
        case .small: return false
        }
    }

    private var byteString: String {
        ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
    }

    private var padding: CGFloat {
        switch size {
        case .hero: return 20
        case .secondary: return 14
        case .medium: return 14
        case .small: return 10
        }
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .hero: return 16
        case .secondary, .medium: return 12
        case .small: return 10
        }
    }

    private var iconFont: Font {
        switch size {
        case .hero: return .system(size: 28)
        case .secondary: return .system(size: 16)
        case .medium: return .system(size: 18)
        case .small: return .system(size: 14)
        }
    }

    private var nameFont: Font {
        switch size {
        case .hero: return .system(size: 20, weight: .semibold)
        case .secondary: return .system(size: 13, weight: .medium)
        case .medium: return .system(size: 14, weight: .medium)
        case .small: return .system(size: 11, weight: .medium)
        }
    }

    private var sizeFont: Font {
        switch size {
        case .hero: return .system(size: 26, weight: .bold, design: .rounded)
        case .secondary: return .system(size: 15, weight: .semibold, design: .rounded)
        case .medium: return .system(size: 16, weight: .semibold, design: .rounded)
        case .small: return .system(size: 12, weight: .semibold, design: .rounded)
        }
    }

    private var nameLineLimit: Int {
        switch size {
        case .hero: return 2
        case .secondary, .medium: return 1
        case .small: return 1
        }
    }
}

// MARK: - List row (for items beyond the top 12)

struct BentoListRow: View {
    let entry: ScanEntry
    let onTap: (ScanEntry) -> Void
    var onRescan: ((ScanEntry) -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        Button {
            if entry.isDirectory { onTap(entry) }
        } label: {
            HStack {
                Image(systemName: entry.category.iconName)
                    .foregroundStyle(entry.category.tintColor)
                    .frame(width: 18)
                Text((entry.path as NSString).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? entry.category.tintColor.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(entry.path)
        .contextMenu {
            if entry.isDirectory, let onRescan {
                Button("Rescan this folder", systemImage: "arrow.clockwise") {
                    onRescan(entry)
                }
            }
        }
    }
}
