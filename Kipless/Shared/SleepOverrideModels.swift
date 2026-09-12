import Foundation

enum SleepOverrideSystemState: Int, Codable, Equatable, Sendable {
    case disabled = 0
    case enabled = 1
    case unknown = 2
}

struct SleepOverrideOwnership: Equatable, Sendable {
    let baselineWasDisabled: Bool
    let modifiedByKipless: Bool
}

enum SleepOverrideStateParser {
    static func parse(_ output: String) -> SleepOverrideSystemState {
        let values = output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> Int? in
                let parts = line.split(whereSeparator: \.isWhitespace)
                guard parts.count == 2, parts[0] == "SleepDisabled" else { return nil }
                return Int(parts[1])
            }

        guard values.count == 1, let value = values.first else { return .unknown }
        switch value {
        case 0: return .disabled
        case 1: return .enabled
        default: return .unknown
        }
    }
}
