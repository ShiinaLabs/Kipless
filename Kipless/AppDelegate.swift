import AppKit

/// There is no Dock icon and no main window, so quitting goes through the
/// popover's Quit button. That funnels every exit through here, which is where
/// the active Session's resources get released.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        WakeSessionManager.shared.prepareForTermination {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        WakeSessionManager.shared.stop()
    }
}
