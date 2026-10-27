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
        guard output.last?.isNewline == true else { return .unknown }

        let lines = output.split(whereSeparator: \.isNewline)
        guard let headerIndex = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }), lines[headerIndex].trimmingCharacters(in: .whitespaces) == "System-wide power settings:" else {
            return .unknown
        }

        var hasSetting = false
        var hasCurrentSettingsHeader = false
        var sleepDisabledState: SleepOverrideSystemState?

        for line in lines.dropFirst(headerIndex + 1) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty else { continue }

            if trimmedLine == "Currently in use:" {
                guard !hasCurrentSettingsHeader else { return .unknown }
                hasCurrentSettingsHeader = true
                continue
            }

            // pmset setting rows are indented beneath the recognized section
            // headings. Requiring a key and value rejects headings, errors,
            // and partial rows without depending on a fixed setting list.
            guard line.first?.isWhitespace == true else { return .unknown }
            let parts = trimmedLine.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2 else { return .unknown }
            hasSetting = true

            guard parts[0] == "SleepDisabled" else { continue }
            guard parts.count == 2, sleepDisabledState == nil else { return .unknown }

            switch parts[1] {
            case "0": sleepDisabledState = .disabled
            case "1": sleepDisabledState = .enabled
            default: return .unknown
            }
        }

        guard hasSetting else { return .unknown }
        return sleepDisabledState ?? .disabled
    }
}
