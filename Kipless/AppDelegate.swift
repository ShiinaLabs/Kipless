import AppKit

/// There is no Dock icon and no main window, so quitting goes through the
/// popover's Quit button. That funnels every exit through here, which is where
/// the active Session's resources get released.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var isTerminating = false
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A timed Session waits on its deadline with a single long sleep rather
        // than a poll, and such a wait is not guaranteed to elapse on schedule
        // across a system sleep. Re-checking on wake is what keeps the deadline
        // — rather than the timer — in charge of when a Session ends.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                WakeSessionManager.shared.systemDidWake()
            }
        }

        // Built now rather than on first use: the Settings button lives in the
        // popover, and the click that reaches it arrives in the middle of a
        // SwiftUI update.
        KiplessSettingsOpener.prepare()
    }

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
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        WakeSessionManager.shared.stop()
    }
}
