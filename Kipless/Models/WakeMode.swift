import Foundation

/// What Kipless keeps awake while a session is running.
enum WakeMode: String, CaseIterable, Identifiable, Sendable {
    /// Blocks idle *system* sleep. The display may still switch off on its own
    /// schedule, which is what you want for long downloads, builds and renders.
    case system

    /// Blocks idle *display* sleep. The system necessarily stays awake too,
    /// since a display cannot be kept on by a sleeping machine.
    case display

    /// Blocks idle system sleep and temporarily overrides normal lid-close
    /// sleep. The display may still switch off on its own schedule.
    case closedLid

    var id: String { rawValue }

    var powerAssertionMode: PowerAssertionMode {
        switch self {
        case .system: .system
        case .display: .display
        case .closedLid: .system
        }
    }

    /// User-facing name for the mode picker.
    var title: String {
        switch self {
        case .system: String(localized: LocalizedStringResource.sessionModeSystemTitle)
        case .display: String(localized: LocalizedStringResource.sessionModeDisplayTitle)
        case .closedLid: String(localized: LocalizedStringResource.sessionModeClosedLidTitle)
        }
    }

    /// Explains the scope of the mode without exposing assertion details.
    var subtitle: String {
        switch self {
        case .system: String(localized: LocalizedStringResource.sessionModeSystemSubtitle)
        case .display: String(localized: LocalizedStringResource.sessionModeDisplaySubtitle)
        case .closedLid: String(localized: LocalizedStringResource.sessionModeClosedLidSubtitle)
        }
    }

    /// Phrase describing the running session.
    var activeDescription: String {
        title
    }
}
