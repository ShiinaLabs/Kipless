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
    // These are the other optional keys printed in pmset's system-wide
    // section. Current power-source settings are validated by their section
    // and row format instead of a complete, version-specific key list.
    private static let recognizedSystemWideSettings: Set<String> = [
        "DestroyFVKeyOnStandby",
        "VACTDisabled"
    ]

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
        var hasCurrentSetting = false
        var hasRecognizedSystemWideSetting = false
        var sleepDisabledState: SleepOverrideSystemState?

        for line in lines.dropFirst(headerIndex + 1) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty else { continue }

            if trimmedLine == "Currently in use:" {
                guard !hasCurrentSettingsHeader else { return .unknown }
                hasCurrentSettingsHeader = true
                continue
            }

            guard line.first?.isWhitespace == true else { return .unknown }
            let parts = trimmedLine.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2 else { return .unknown }

            let settingName = String(parts[0])
            guard isSettingName(parts[0]) else { return .unknown }
            hasSetting = true
            if hasCurrentSettingsHeader { hasCurrentSetting = true }
            if recognizedSystemWideSettings.contains(settingName) {
                hasRecognizedSystemWideSetting = true
            }

            if settingName == "SleepDisabled" {
                guard parts.count == 2, sleepDisabledState == nil else { return .unknown }

                switch parts[1] {
                case "0": sleepDisabledState = .disabled
                case "1": sleepDisabledState = .enabled
                default: return .unknown
                }
                continue
            }

            let value = String(parts[1])
            let isIntegerValue = Int(value) != nil
            let isPathValue = value.hasPrefix("/")
            guard isIntegerValue || isPathValue else { return .unknown }

            if parts.count > 2, !isPathValue {
                let annotation = parts.dropFirst(2).joined(separator: " ")
                guard annotation.hasPrefix("("), annotation.hasSuffix(")") else {
                    return .unknown
                }
            }
        }

        guard hasSetting,
              sleepDisabledState != nil
                || (hasCurrentSettingsHeader && hasCurrentSetting)
                || hasRecognizedSystemWideSetting else {
            return .unknown
        }
        return sleepDisabledState ?? .disabled
    }

    private static func isSettingName(_ token: Substring) -> Bool {
        guard let first = token.first, first.isASCII, first.isLetter else { return false }
        return token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
