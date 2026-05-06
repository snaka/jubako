import SwiftUI
import AppKit

@main
struct JubakoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard SnapshotStore.hasPendingSave else { return .terminateNow }
        // Wait for the save to finish before letting the user quit, so the
        // snapshot is intact for the next launch.
        Task { @MainActor in
            while SnapshotStore.hasPendingSave {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
