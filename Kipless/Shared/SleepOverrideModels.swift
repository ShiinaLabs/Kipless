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
        let lines = output.split(whereSeparator: \.isNewline)
        guard let headerIndex = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }), lines[headerIndex].trimmingCharacters(in: .whitespaces) == "System-wide power settings:" else {
            return .unknown
        }

        var currentSettingsIndex: Int?
        for index in lines.indices where index > headerIndex {
            let trimmedLine = lines[index].trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty else { continue }
            if trimmedLine == "Currently in use:" {
                guard currentSettingsIndex == nil else { return .unknown }
                currentSettingsIndex = index
            } else if lines[index].first?.isWhitespace != true {
                return .unknown
            }
        }

        let systemWideEnd = currentSettingsIndex ?? lines.endIndex
        var explicitState: SleepOverrideSystemState?
        for line in lines[(headerIndex + 1)..<systemWideEnd] {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.first == "SleepDisabled" else { continue }
            guard line.first?.isWhitespace == true,
                  parts.count == 2,
                  explicitState == nil else {
                return .unknown
            }

            switch parts[1] {
            case "0": explicitState = .disabled
            case "1": explicitState = .enabled
            default: return .unknown
            }
        }
        if let explicitState { return explicitState }

        if let currentSettingsIndex {
            var hasSleepSetting = false
            var hasMisplacedSleepDisabled = false
            for line in lines.dropFirst(currentSettingsIndex + 1) {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard !trimmedLine.isEmpty else { continue }
                guard line.first?.isWhitespace == true else { return .unknown }

                let parts = trimmedLine.split(whereSeparator: \.isWhitespace)
                guard let settingName = parts.first else { continue }
                if settingName == "SleepDisabled" {
                    hasMisplacedSleepDisabled = true
                } else if settingName == "sleep" {
                    guard parts.count >= 2, Int(parts[1]) != nil else { return .unknown }
                    hasSleepSetting = true
                }
            }

            guard hasSleepSetting, !hasMisplacedSleepDisabled else { return .unknown }
            return .disabled
        }

        // pmset also prints these optional Boolean keys in the system-wide
        // section. They provide a narrow fallback when that section has no
        // Currently-in-use block, without enumerating all power settings.
        for line in lines[(headerIndex + 1)..<systemWideEnd] {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.first == "DestroyFVKeyOnStandby" || parts.first == "VACTDisabled" else {
                continue
            }
            guard line.first?.isWhitespace == true,
                  parts.count == 2,
                  parts[1] == "0" || parts[1] == "1" else {
                return .unknown
            }
            return .disabled
        }

        return .unknown
    }
}
