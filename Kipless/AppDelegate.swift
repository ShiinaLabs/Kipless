import AppKit

/// There is no Dock icon and no main window, so quitting goes through the
/// popover's Quit button. That funnels every exit through here, which is where
/// the assertion gets released.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        WakeSessionManager.shared.stop()
    }
}
