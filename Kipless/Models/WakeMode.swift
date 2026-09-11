import Foundation

/// What Kipless keeps awake while a session is running.
enum WakeMode: String, CaseIterable, Identifiable, Sendable {
    /// Blocks idle *system* sleep. The display may still switch off on its own
    /// schedule, which is what you want for long downloads, builds and renders.
    case system

    /// Blocks idle *display* sleep. The system necessarily stays awake too,
    /// since a display cannot be kept on by a sleeping machine.
    case display

    var id: String { rawValue }

    /// User-facing name for the mode picker.
    var title: String {
        switch self {
        case .system: String(localized: KiplessStrings.modeSystemTitle)
        case .display: String(localized: KiplessStrings.modeDisplayTitle)
        }
    }

    /// Explains the scope of the mode without exposing assertion details.
    var subtitle: String {
        switch self {
        case .system: String(localized: KiplessStrings.modeSystemSubtitle)
        case .display: String(localized: KiplessStrings.modeDisplaySubtitle)
        }
    }

    /// Phrase describing the running session.
    var activeDescription: String {
        title
    }
}
