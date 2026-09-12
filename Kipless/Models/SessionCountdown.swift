import Foundation

/// Turns a remaining-seconds value into the one line the popover shows.
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
