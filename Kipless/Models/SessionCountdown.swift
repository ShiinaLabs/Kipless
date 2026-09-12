import Foundation

/// Turns a remaining-seconds value into a countdown written out in words.
///
/// Both places that draw a countdown draw a clock instead — "29:43" in the
/// popover, "29m" in the menu bar — so this is the form to read out rather than
/// to look at, and it is what the menu bar countdown is announced as.
enum SessionCountdown {
    static func text(forRemainingSeconds seconds: Int) -> String {
        let seconds = max(0, seconds)

        if seconds >= 3600 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return minutes == 0
                ? String(localized: LocalizedStringResource.sessionCountdownHours(hours))
                : String(localized: LocalizedStringResource.sessionCountdownHoursAndMinutes(hours, minutes))
        }

        if seconds >= 60 {
            return String(localized: LocalizedStringResource.sessionCountdownMinutes(seconds / 60))
        }

        return String(localized: LocalizedStringResource.sessionCountdownLessThanMinute)
    }
}
