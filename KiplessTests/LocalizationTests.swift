import Foundation
import XCTest
@testable import Kipless

final class LocalizationTests: XCTestCase {
    func testLocalizationResourcesUseSemanticKeys() {
        let keys = [
            LocalizedStringResource.appActionQuit.key,
            LocalizedStringResource.appActionQuitHelp.key,
            LocalizedStringResource.appName.key,
            LocalizedStringResource.durationHour1.key,
            LocalizedStringResource.durationHour2.key,
            LocalizedStringResource.durationIndefinite.key,
            LocalizedStringResource.durationMinutes15.key,
            LocalizedStringResource.durationMinutes30.key,
            LocalizedStringResource.errorAssertionCreation(0).key,
            LocalizedStringResource.menuStatusActive.key,
            LocalizedStringResource.menuStatusInactive.key,
            LocalizedStringResource.permissionClosedLidApprovalDismiss.key,
            LocalizedStringResource.permissionClosedLidApprovalMessage.key,
            LocalizedStringResource.permissionClosedLidApprovalOpenSettings.key,
            LocalizedStringResource.permissionClosedLidApprovalTitle.key,
            LocalizedStringResource.permissionClosedLidErrorConnectionInvalidated.key,
            LocalizedStringResource.permissionClosedLidErrorConnectionUnavailable.key,
            LocalizedStringResource.permissionClosedLidErrorHelperInterface.key,
            LocalizedStringResource.permissionClosedLidErrorHelperRejected.key,
            LocalizedStringResource.permissionClosedLidErrorNotResponding.key,
            LocalizedStringResource.permissionClosedLidErrorUnknownState(0).key,
            LocalizedStringResource.sessionActionStart.key,
            LocalizedStringResource.sessionActionStop.key,
            LocalizedStringResource.sessionCountdownHours(1).key,
            LocalizedStringResource.sessionCountdownHoursAndMinutes(1, 1).key,
            LocalizedStringResource.sessionCountdownLessThanMinute.key,
            LocalizedStringResource.sessionCountdownMinutes(1).key,
            LocalizedStringResource.sessionDurationTitle.key,
            LocalizedStringResource.sessionIndefiniteActive.key,
            LocalizedStringResource.sessionIndefiniteIdle.key,
            LocalizedStringResource.sessionModeClosedLidSubtitle.key,
            LocalizedStringResource.sessionModeClosedLidTitle.key,
            LocalizedStringResource.sessionModeDisplaySubtitle.key,
            LocalizedStringResource.sessionModeDisplayTitle.key,
            LocalizedStringResource.sessionModeExplanation.key,
            LocalizedStringResource.sessionModeSystemSubtitle.key,
            LocalizedStringResource.sessionModeSystemTitle.key,
            LocalizedStringResource.sessionTimeRemaining.key,
            LocalizedStringResource.settingsAboutDescription.key,
            LocalizedStringResource.settingsAboutLicense.key,
            LocalizedStringResource.settingsAboutPrivacy.key,
            LocalizedStringResource.settingsAboutVersion("1.0").key,
            LocalizedStringResource.settingsActionOpen.key,
            LocalizedStringResource.settingsLaunchAtLoginApproval.key,
            LocalizedStringResource.settingsLaunchAtLoginDescription.key,
            LocalizedStringResource.settingsLaunchAtLoginTitle.key,
            LocalizedStringResource.settingsMenuBarCountdownDescription.key,
            LocalizedStringResource.settingsMenuBarCountdownTitle.key,
            LocalizedStringResource.settingsModeTableColumnDisplaySleep.key,
            LocalizedStringResource.settingsModeTableColumnIdleSleep.key,
            LocalizedStringResource.settingsModeTableColumnLidSleep.key,
            LocalizedStringResource.settingsModeTableColumnMode.key,
            LocalizedStringResource.settingsModeTableStatusAllowed.key,
            LocalizedStringResource.settingsModeTableStatusBlocked.key,
            LocalizedStringResource.settingsSectionAbout.key,
            LocalizedStringResource.settingsSectionGeneral.key,
            LocalizedStringResource.settingsSectionWakeModes.key,
            LocalizedStringResource.settingsTitle.key,
            LocalizedStringResource.settingsWindowTitle.key
        ]

        XCTAssertEqual(keys.count, Set(keys).count)
        XCTAssertTrue(keys.allSatisfy { $0.contains(".") })
        XCTAssertFalse(keys.contains("Keep Mac Awake"))
        XCTAssertFalse(keys.contains("Keep Mac + Display Awake"))
    }

    func testCoreCopyHasEnglishFallbackValues() {
        XCTAssertEqual(
            String(localized: LocalizedStringResource.sessionModeSystemTitle),
            "System"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource.sessionModeDisplayTitle),
            "Display"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource.sessionModeExplanation),
            "Choose how your Mac stays awake."
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource.sessionModeClosedLidTitle),
            "Closed Lid"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource.permissionClosedLidApprovalTitle),
            "Allow Closed Lid"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource.permissionClosedLidApprovalOpenSettings),
            "Open Login Items"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource.permissionClosedLidApprovalMessage),
            "In System Settings › General › Login Items, turn on Kipless in the background apps list to use Closed Lid mode."
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource.permissionClosedLidApprovalDismiss),
            "Not Now"
        )
        // The helper's failures are user-visible, so they live in the catalog
        // rather than as literals in the client.
        XCTAssertEqual(
            String(localized: LocalizedStringResource.permissionClosedLidErrorNotResponding),
            "The privileged helper did not respond, so Closed Lid could not start"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource.permissionClosedLidErrorUnknownState(7)),
            "Helper returned an unknown SleepDisabled state (7)"
        )
    }

    func testIndefinitePresentationCopyHasEnglishFallbackValues() {
        XCTAssertEqual(
            String(localized: LocalizedStringResource.sessionIndefiniteIdle),
            "Until stopped"
        )
        XCTAssertEqual(
            String(localized: LocalizedStringResource.sessionIndefiniteActive),
            "Keeping awake"
        )
    }

    /// The tests run with English forced by the scheme, so the shipped
    /// translations are checked through their own bundles instead. A key whose
    /// copy differs in every language keeps a missing or untranslated resource
    /// from passing silently.
    func testEveryShippedLocalizationResolvesItsOwnCopy() {
        let sampleKeys = [
            "permission.closedLid.error.notResponding",
            "settings.menuBarCountdown.title",
            "settings.menuBarCountdown.description"
        ]
        let english = sampleKeys.map {
            Bundle.main.localizedString(forKey: $0, value: nil, table: nil)
        }
        let shipped = ["de", "es", "fr", "it", "ja", "ko", "pt-BR", "zh-Hans", "zh-Hant"]

        for language in shipped {
            XCTAssertTrue(
                Bundle.main.localizations.contains(language),
                "\(language) is missing from the app bundle"
            )

            guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
                  let bundle = Bundle(path: path)
            else {
                XCTFail("\(language).lproj could not be opened")
                continue
            }

            for (index, key) in sampleKeys.enumerated() {
                let translated = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertFalse(translated.isEmpty, "\(language) has no value for \(key)")
                XCTAssertNotEqual(translated, english[index], "\(language) fell back to English for \(key)")
            }
        }
    }
}
