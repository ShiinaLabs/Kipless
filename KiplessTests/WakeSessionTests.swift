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
        XCTAssertEqual(WakeMode.allCases, [.system, .display])
    }

    func testWakeModesUseHierarchicalUserFacingLabels() {
        XCTAssertEqual(WakeMode.system.title, "Let the screen turn off")
        XCTAssertEqual(
            WakeMode.system.subtitle,
            "Your Mac keeps working. Lock Screen follows your macOS settings."
        )
        XCTAssertEqual(WakeMode.display.title, "Keep the screen on")
        XCTAssertEqual(WakeMode.display.subtitle, "Your Mac and screen stay awake.")
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
