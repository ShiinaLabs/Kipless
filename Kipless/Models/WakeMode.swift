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

    /// Short label for the mode picker.
    var title: String {
        switch self {
        case .system: "System"
        case .display: "Display"
        }
    }

    /// Phrase describing the running session, e.g. "System awake".
    var activeDescription: String {
        switch self {
        case .system: "System awake"
        case .display: "Display awake"
        }
    }
}
