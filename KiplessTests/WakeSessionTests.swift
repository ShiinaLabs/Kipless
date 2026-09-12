import AppKit
import XCTest
@testable import Kipless

final class WakeSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testTimedSessionGetsAnAbsoluteDeadline() {
        let session = WakeSession(mode: .system, startedAt: start, duration: .minutes15)

        XCTAssertEqual(session.expiresAt, start.addingTimeInterval(15 * 60))
    }

    func testPresetDurations() {
        XCTAssertEqual(WakeDuration.minutes15.seconds, 900)
        XCTAssertEqual(WakeDuration.minutes30.seconds, 1800)
        XCTAssertEqual(WakeDuration.hour1.seconds, 3600)
        XCTAssertEqual(WakeDuration.hour2.seconds, 7200)
        XCTAssertNil(WakeDuration.indefinite.seconds)
    }

    func testIndefiniteSessionHasNoDeadline() {
        let session = WakeSession(mode: .display, startedAt: start, duration: .indefinite)

        XCTAssertNil(session.expiresAt)
    }

    func testEveryDurationIsOfferedExactlyOnce() {
        XCTAssertEqual(
            WakeDuration.allCases,
            [.minutes15, .minutes30, .hour1, .hour2, .indefinite]
        )
        XCTAssertEqual(WakeMode.allCases, [.system, .display, .closedLid])
    }

    func testWakeModesUseHierarchicalUserFacingLabels() {
        XCTAssertEqual(WakeMode.system.title, "System")
        XCTAssertEqual(
            WakeMode.system.subtitle,
            "Keep Mac awake. Display may turn off."
        )
        XCTAssertEqual(WakeMode.display.title, "Display")
        XCTAssertEqual(WakeMode.display.subtitle, "Keep Mac and display awake.")
        XCTAssertEqual(WakeMode.closedLid.title, "Closed Lid")
        XCTAssertEqual(
            WakeMode.closedLid.subtitle,
            "Keep Mac awake when the lid is closed."
        )
    }

    func testSettingsCopyKeepsThePanelConcise() {
        XCTAssertEqual(SettingsCopy.launchAtLoginDescription, "Start Kipless automatically when you sign in.")
        XCTAssertEqual(SettingsCopy.aboutDescription, "Lightweight and private.")
    }

    func testKiplessAccentUsesTheCurrentControlAccent() {
        XCTAssertEqual(KiplessTheme.accentNSColor, NSColor.controlAccentColor)
    }

    func testAppDoesNotOverrideTheSystemAccent() {
        let appBundle = Bundle(identifier: "com.kaoru.kipless")

        XCTAssertNotNil(appBundle)
        XCTAssertNil(appBundle?.object(forInfoDictionaryKey: "NSAccentColorName"))
    }

    func testSettingsOpenerUsesTheDedicatedSettingsWindow() {
        XCTAssertEqual(KiplessSettingsOpener.windowTitle, "Kipless Settings")
    }

    @MainActor
    func testSettingsOpenerShowsTheDedicatedSettingsWindow() {
        KiplessSettingsOpener.open()
        defer { NSApp.windows.first(where: { $0.title == KiplessSettingsOpener.windowTitle })?.close() }

        XCTAssertTrue(NSApp.windows.contains(where: { $0.title == KiplessSettingsOpener.windowTitle && $0.isVisible }))
    }
}
