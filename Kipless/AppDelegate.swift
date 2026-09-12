import AppKit

/// There is no Dock icon and no main window, so quitting goes through the
/// popover's Quit button. That funnels every exit through here, which is where
/// the active Session's resources get released.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var isTerminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A second terminate request while the first is still unwinding must
        // not produce a second reply.
        guard !isTerminating else { return .terminateLater }

        isTerminating = true
        WakeSessionManager.shared.prepareForTermination {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        WakeSessionManager.shared.stop()
    }
}
