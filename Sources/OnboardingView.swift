import SwiftUI
import AppKit

struct OnboardingView: View {
    let onContinueWithout: () -> Void
    let onRecheck: () -> Void
    @State private var showRecheckFailedHint = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 8) {
                Text("Welcome to Jubako")
                    .font(.system(size: 28, weight: .bold))
                Text("To find what's eating your disk space accurately,\nJubako needs Full Disk Access.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                instructionRow(num: 1, text: "Click **Open System Settings** below.")
                instructionRow(num: 2, text: "Find **Jubako** in the list and toggle it on. (Use the **+** button to add it if it's not there.)")
                instructionRow(num: 3, text: "Quit Jubako (⌘Q) and reopen it for the change to take effect.")
            }
            .padding(20)
            .frame(maxWidth: 520)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(12)

            VStack(spacing: 10) {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("Open System Settings")
                        .frame(minWidth: 240)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                Button("I've granted access — recheck") {
                    if FDAProbe.hasAccess() {
                        onRecheck()
                    } else {
                        showRecheckFailedHint = true
                    }
                }
                .buttonStyle(.borderless)

                if showRecheckFailedHint {
                    Text("Still not detected. Try quitting and reopening Jubako.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button("Continue without Full Disk Access") {
                    onContinueWithout()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
            }

            Spacer()

            Text("Jubako only reads file sizes and timestamps. Nothing leaves your Mac.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
    }

    private func instructionRow(num: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(num).")
                .font(.body.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 18, alignment: .leading)
            Text(.init(text))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    OnboardingView(onContinueWithout: {}, onRecheck: {})
        .frame(width: 720, height: 600)
}
