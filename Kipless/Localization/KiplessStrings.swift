import Foundation

/// Semantic localization resources used by the app's user-facing surface.
///
/// Keys are intentionally stable identifiers rather than English copy. The
/// English values here are the source-language fallback and can be replaced by
/// localized values in `Localizable.xcstrings` without changing Swift code.
enum KiplessStrings {
    static let appName = LocalizedStringResource(
        "app.name",
        defaultValue: "Kipless",
        comment: "The product name."
    )

    static let settingsWindowTitle = LocalizedStringResource(
        "settings.window.title",
        defaultValue: "Kipless Settings",
        comment: "The title of the settings window."
    )
    static let settingsTitle = LocalizedStringResource(
        "settings.title",
        defaultValue: "Settings",
        comment: "The settings screen title."
    )
    static let settingsGeneralSection = LocalizedStringResource(
        "settings.section.general",
        defaultValue: "General",
        comment: "The general settings section title."
    )
    static let settingsAboutSection = LocalizedStringResource(
        "settings.section.about",
        defaultValue: "About",
        comment: "The about settings section title."
    )
    static let settingsWakeModesSection = LocalizedStringResource(
        "settings.section.wakeModes",
        defaultValue: "Wake modes",
        comment: "The settings section that explains each wake mode."
    )
    static let settingsModeColumnMode = LocalizedStringResource(
        "settings.modeTable.column.mode",
        defaultValue: "Mode",
        comment: "Table header for the wake mode name."
    )
    static let settingsModeColumnIdleSleep = LocalizedStringResource(
        "settings.modeTable.column.idleSleep",
        defaultValue: "Idle sleep",
        comment: "Table header for whether idle system sleep is blocked."
    )
    static let settingsModeColumnDisplaySleep = LocalizedStringResource(
        "settings.modeTable.column.displaySleep",
        defaultValue: "Display sleep",
        comment: "Table header for whether display sleep is blocked."
    )
    static let settingsModeColumnLidSleep = LocalizedStringResource(
        "settings.modeTable.column.lidSleep",
        defaultValue: "Lid-close sleep",
        comment: "Table header for whether lid-close sleep is blocked."
    )
    static let settingsModeBlocked = LocalizedStringResource(
        "settings.modeTable.status.blocked",
        defaultValue: "Blocked",
        comment: "Status meaning a sleep behavior is prevented."
    )
    static let settingsModeAllowed = LocalizedStringResource(
        "settings.modeTable.status.allowed",
        defaultValue: "Allowed",
        comment: "Status meaning a sleep behavior follows macOS settings."
    )
    static let settingsLaunchAtLoginTitle = LocalizedStringResource(
        "settings.launchAtLogin.title",
        defaultValue: "Launch at Login",
        comment: "The launch at login setting title."
    )
    static let settingsLaunchAtLoginDescription = LocalizedStringResource(
        "settings.launchAtLogin.description",
        defaultValue: "Start Kipless automatically when you sign in.",
        comment: "Explains what the launch at login setting does."
    )
    static let settingsLaunchAtLoginApproval = LocalizedStringResource(
        "settings.launchAtLogin.approval",
        defaultValue: "Allow Kipless in System Settings › General › Login Items to finish turning this on.",
        comment: "Explains how to approve launch at login."
    )
    static let settingsAboutDescription = LocalizedStringResource(
        "settings.about.description",
        defaultValue: "Lightweight and private.",
        comment: "Short product description in the about section."
    )
    static let settingsPrivacyDescription = LocalizedStringResource(
        "settings.about.privacy",
        defaultValue: "No accounts, telemetry, or network connections.",
        comment: "Privacy promise in the about section."
    )
    static let settingsLicense = LocalizedStringResource(
        "settings.about.license",
        defaultValue: "MPL-2.0",
        comment: "The app's software license."
    )
    static func settingsVersion(_ version: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "settings.about.version",
            defaultValue: "Version \(version)",
            comment: "The app version in the about section."
        )
    }

    static let modeExplanation = LocalizedStringResource(
        "session.mode.explanation",
        defaultValue: "Choose how your Mac stays awake.",
        comment: "Introduces the mutually exclusive wake modes."
    )
    static let modeSystemTitle = LocalizedStringResource(
        "session.mode.system.title",
        defaultValue: "System",
        comment: "Mode that keeps the Mac awake while allowing the display to turn off."
    )
    static let modeSystemSubtitle = LocalizedStringResource(
        "session.mode.system.subtitle",
        defaultValue: "Keep Mac awake. Display may turn off.",
        comment: "Explains the System wake mode."
    )
    static let modeDisplayTitle = LocalizedStringResource(
        "session.mode.display.title",
        defaultValue: "Display",
        comment: "Mode that keeps both the Mac and display awake."
    )
    static let modeDisplaySubtitle = LocalizedStringResource(
        "session.mode.display.subtitle",
        defaultValue: "Keep Mac and display awake.",
        comment: "Explains the Display wake mode."
    )
    static let modeClosedLidTitle = LocalizedStringResource(
        "session.mode.closedLid.title",
        defaultValue: "Closed Lid",
        comment: "Mode that keeps a Mac awake when its lid is closed."
    )
    static let modeClosedLidSubtitle = LocalizedStringResource(
        "session.mode.closedLid.subtitle",
        defaultValue: "Keep Mac awake when the lid is closed.",
        comment: "Explains the Closed Lid wake mode."
    )

    static let sessionDurationTitle = LocalizedStringResource(
        "session.duration.title",
        defaultValue: "Duration",
        comment: "The duration picker label."
    )
    static let sessionStart = LocalizedStringResource(
        "session.action.start",
        defaultValue: "Start session",
        comment: "Accessibility label and help text for starting a session."
    )
    static let sessionStop = LocalizedStringResource(
        "session.action.stop",
        defaultValue: "Stop session",
        comment: "Accessibility label and help text for stopping a session."
    )
    static let sessionTimeRemaining = LocalizedStringResource(
        "session.timeRemaining",
        defaultValue: "Session time remaining",
        comment: "Accessibility label for the session countdown."
    )
    static let sessionIndefiniteIdle = LocalizedStringResource(
        "session.indefinite.idle",
        defaultValue: "Until stopped",
        comment: "Status shown before an indefinite session starts."
    )
    static let sessionIndefiniteActive = LocalizedStringResource(
        "session.indefinite.active",
        defaultValue: "Keeping awake",
        comment: "Status shown while an indefinite session is active."
    )
    static func countdownHours(_ hours: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "session.countdown.hours",
            defaultValue: "\(hours) hr remaining",
            comment: "Countdown text for a remaining duration measured in whole hours."
        )
    }
    static func countdownHoursAndMinutes(_ hours: Int, _ minutes: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "session.countdown.hoursAndMinutes",
            defaultValue: "\(hours) hr \(minutes) min remaining",
            comment: "Countdown text for remaining hours and minutes."
        )
    }
    static func countdownMinutes(_ minutes: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "session.countdown.minutes",
            defaultValue: "\(minutes) min remaining",
            comment: "Countdown text for a remaining duration measured in whole minutes."
        )
    }
    static let countdownLessThanMinute = LocalizedStringResource(
        "session.countdown.lessThanMinute",
        defaultValue: "Less than a minute remaining",
        comment: "Countdown text for less than one minute remaining."
    )
    static let durationMinutes15 = LocalizedStringResource(
        "duration.minutes15",
        defaultValue: "15 minutes",
        comment: "A 15-minute session duration."
    )
    static let durationMinutes30 = LocalizedStringResource(
        "duration.minutes30",
        defaultValue: "30 minutes",
        comment: "A 30-minute session duration."
    )
    static let durationHour1 = LocalizedStringResource(
        "duration.hour1",
        defaultValue: "1 hour",
        comment: "A one-hour session duration."
    )
    static let durationHour2 = LocalizedStringResource(
        "duration.hour2",
        defaultValue: "2 hours",
        comment: "A two-hour session duration."
    )
    static let durationIndefinite = LocalizedStringResource(
        "duration.indefinite",
        defaultValue: "Indefinitely",
        comment: "A session that ends only when the user stops it."
    )
    static let menuStatusActive = LocalizedStringResource(
        "menu.status.active",
        defaultValue: "Kipless is keeping your Mac awake",
        comment: "Accessibility label when a wake session is active."
    )
    static let menuStatusInactive = LocalizedStringResource(
        "menu.status.inactive",
        defaultValue: "Kipless is inactive",
        comment: "Accessibility label when no wake session is active."
    )
    static let settingsAction = LocalizedStringResource(
        "settings.action.open",
        defaultValue: "Settings",
        comment: "The button that opens settings."
    )
    static let quitAction = LocalizedStringResource(
        "app.action.quit",
        defaultValue: "Quit Kipless",
        comment: "Accessibility label for quitting the app."
    )
    static let quitHelp = LocalizedStringResource(
        "app.action.quit.help",
        defaultValue: "Quit Kipless and release the wake session",
        comment: "Help text for the quit button."
    )
    static func assertionCreationError(code: IOReturn) -> LocalizedStringResource {
        LocalizedStringResource(
            "error.assertionCreation",
            defaultValue: "Could not keep your Mac awake (IOKit error \(code)).",
            comment: "Shown when macOS rejects a power assertion."
        )
    }

    static let allResources: [LocalizedStringResource] = [
        appName,
        settingsWindowTitle,
        settingsTitle,
        settingsGeneralSection,
        settingsAboutSection,
        settingsWakeModesSection,
        settingsModeColumnMode,
        settingsModeColumnIdleSleep,
        settingsModeColumnDisplaySleep,
        settingsModeColumnLidSleep,
        settingsModeBlocked,
        settingsModeAllowed,
        settingsLaunchAtLoginTitle,
        settingsLaunchAtLoginDescription,
        settingsLaunchAtLoginApproval,
        settingsAboutDescription,
        settingsPrivacyDescription,
        settingsLicense,
        modeExplanation,
        modeSystemTitle,
        modeSystemSubtitle,
        modeDisplayTitle,
        modeDisplaySubtitle,
        modeClosedLidTitle,
        modeClosedLidSubtitle,
        sessionDurationTitle,
        sessionStart,
        sessionStop,
        sessionTimeRemaining,
        sessionIndefiniteIdle,
        sessionIndefiniteActive,
        durationMinutes15,
        durationMinutes30,
        durationHour1,
        durationHour2,
        durationIndefinite,
        menuStatusActive,
        menuStatusInactive,
        settingsAction,
        quitAction,
        quitHelp
    ]
}
