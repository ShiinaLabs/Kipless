import AppKit

/// Keeps Kipless able to be frontmost for as long as something needs a window.
///
/// An accessory app cannot reliably bring a window to the front: macOS treats
/// activation as a request it may refuse when the user did not just switch to
/// the app, and the popover that both callers are reached from is a
/// non-activating panel. Becoming a regular app for as long as a window is up
/// is what turns that request into one the system grants.
///
/// Two things hold it: the Settings window, and Sparkle's update windows. This
/// counts rather than flags, so one of them going away does not drop the app
/// back to an accessory and out from under the other.
@MainActor
enum AppActivation {
    private static var holders = 0

    /// Asks to be a regular, active app. Safe to call when one is already held;
    /// doing so re-fronts rather than stacking anything.
    static func begin() {
        holders += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Gives the hold back. The app returns to being a menu bar app with no
    /// Dock icon only once the last one is gone.
    static func end() {
        guard holders > 0 else { return }

        holders -= 1
        guard holders == 0 else { return }

        NSApp.setActivationPolicy(.accessory)
    }
}
