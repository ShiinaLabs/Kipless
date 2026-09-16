import AppKit
import SwiftUI

@main
@MainActor
struct KiplessAppStore: App {
    @NSApplicationDelegateAdaptor(AppStoreAppDelegate.self)
    private var appDelegate

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

@MainActor
final class AppStoreAppDelegate: NSObject, NSApplicationDelegate {
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                WakeSessionManager.shared.systemDidWake()
            }
        }

        KiplessSettingsOpener.prepare()

        guard CommandLine.arguments.contains("--smoke-test") else { return }

        do {
            try Self.runPowerAssertionSmokeTest()
            print("KIPLESS_APP_STORE_POWER_ASSERTIONS_PASS")
        } catch {
            fputs("KIPLESS_APP_STORE_POWER_ASSERTIONS_FAIL: \(error)\n", stderr)
        }

        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        WakeSessionManager.shared.stop()
    }

    private static func runPowerAssertionSmokeTest() throws {
        for mode in [PowerAssertionMode.system, .display] {
            let assertionID = try PowerAssertionDriver.acquire(for: mode)
            PowerAssertionDriver.release(assertionID)
        }
    }
}
