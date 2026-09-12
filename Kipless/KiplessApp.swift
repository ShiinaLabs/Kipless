import SwiftUI

@main
@MainActor
struct KiplessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var sessionManager = WakeSessionManager.shared

    var body: some Scene {
        MenuBarExtra {
            KiplessPopoverView()
                .environment(sessionManager)
        } label: {
            MenuBarLabel()
                .environment(sessionManager)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
