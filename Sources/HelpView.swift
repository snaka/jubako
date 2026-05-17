import SwiftUI

/// In-app reference that explains the UI elements which aren't obvious at a
/// glance. Shown as a sheet from the main window — reachable from the help
/// button on the disk usage bar and from Help → "Jubako Help" in the menu
/// bar.
struct HelpView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    diskUsageSection
                    rescanSection
                    deferredSection
                    snapshotSection
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 520)
    }

    private var header: some View {
        HStack {
            Text("Jubako Help")
                .font(.title2.weight(.semibold))
            Spacer()
            Button("Done", action: onDismiss)
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private var diskUsageSection: some View {
        section(title: "Disk usage bar", icon: "chart.bar.fill") {
            entry(
                swatch: .orange,
                term: "Scanned",
                body: "Bytes Jubako found and accounted for in the current scan."
            )
            entry(
                swatch: .secondary,
                term: "Other",
                body: "Used space that lives on the same volume but isn't covered by this scan — system files, folders skipped by permissions, or paths outside the current root."
            )
            entry(
                swatch: .green,
                term: "Free",
                body: "Space the volume reports as available, including purgeable storage macOS can reclaim on demand."
            )
            Text("The volume label on the right names the disk containing the current scan root.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var rescanSection: some View {
        section(title: "Rescanning", icon: "arrow.clockwise") {
            bullet("The button at the top-left runs a fresh scan of the whole home directory.")
            bullet("Right-clicking any Bento card or list row offers \"Rescan this folder\" so you can refresh a single subtree without re-walking everything.")
            bullet("Right-clicking the breadcrumb area offers \"Rescan current folder\" with the same effect for the folder you're currently viewing.")
        }
    }

    private var deferredSection: some View {
        section(title: "Skipped folders", icon: "lock.shield") {
            Text("Some folders in your home — Mail, Messages, Containers, etc. — are TCC-protected and require Full Disk Access. They appear in the blue banner with a \"Retry\" button after you grant the permission.")
                .font(.callout)
                .foregroundStyle(.primary)
            Text("Until access is granted, those subtrees are excluded from totals and from the Scanned segment of the disk usage bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var snapshotSection: some View {
        section(title: "Snapshot persistence", icon: "externaldrive.badge.checkmark") {
            Text("Each scan is written to `~/Library/Application Support/Jubako/snapshot.bin` so the next launch can show the previous result immediately. Snapshots older than a week are flagged as stale in the banner.")
                .font(.callout)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.headline)
            }
            content()
        }
    }

    private func entry(swatch: Color, term: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(swatch)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(term)
                    .font(.callout.weight(.semibold))
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    HelpView(onDismiss: {})
}
