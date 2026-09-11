import Foundation

/// The fixed set of session lengths Kipless offers.
///
/// v1.0 deliberately has no custom durations — five presets cover the real
/// cases without adding a picker, a text field and the validation around them.
enum WakeDuration: String, CaseIterable, Identifiable, Sendable {
    case minutes15
    case minutes30
    case hour1
    case hour2
    case indefinite

    var id: String { rawValue }

    /// The length of the session, or `nil` when it runs until stopped.
    var seconds: TimeInterval? {
        switch self {
        case .minutes15: 15 * 60
        case .minutes30: 30 * 60
        case .hour1: 60 * 60
        case .hour2: 120 * 60
        case .indefinite: nil
        }
    }

    /// Short label for the duration picker.
    var title: String {
        switch self {
        case .minutes15: "15 minutes"
        case .minutes30: "30 minutes"
        case .hour1: "1 hour"
        case .hour2: "2 hours"
        case .indefinite: "Indefinitely"
        }
    }
}
