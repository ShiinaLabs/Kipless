import Foundation

/// Turns a remaining-seconds value into the one line the popover shows.
enum SessionCountdown {
    static func text(forRemainingSeconds seconds: Int) -> String {
        let seconds = max(0, seconds)

        if seconds >= 3600 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            let hourPart = hours == 1 ? "1 hr" : "\(hours) hr"
            return minutes == 0
                ? "\(hourPart) remaining"
                : "\(hourPart) \(minutes) min remaining"
        }

        if seconds >= 60 {
            return "\(seconds / 60) min remaining"
        }

        return "Less than a minute remaining"
    }
}
