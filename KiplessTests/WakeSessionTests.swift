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
        XCTAssertEqual(SettingsCopy.closedLidApprovalTitle, "Allow Closed Lid")
        XCTAssertEqual(
            SettingsCopy.closedLidApprovalMessage,
            "In System Settings › General › Login Items, turn on Kipless in the background apps list to use Closed Lid mode."
        )
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
    func testApprovalAlertOpensLoginItemsOnlyWhenAccepted() {
        let recorder = ApprovalAlertRecorder()

        ClosedLidApprovalAlert.present(
            runAlert: { title, message, accept, dismiss in
                recorder.texts = [title, message, accept, dismiss]
                return true
            },
            openLoginItems: { recorder.openCount += 1 }
        )

        XCTAssertEqual(recorder.texts.first, "Allow Closed Lid")
        XCTAssertEqual(recorder.texts[2], "Open Login Items")
        XCTAssertEqual(recorder.texts.last, "Not Now")
        XCTAssertEqual(recorder.openCount, 1)

        ClosedLidApprovalAlert.present(
            runAlert: { _, _, _, _ in false },
            openLoginItems: { recorder.openCount += 1 }
        )

        XCTAssertEqual(recorder.openCount, 1, "Dismissing the dialog must not open Login Items")
    }

    @MainActor
    func testSettingsWindowIsTallEnoughForEveryCard() {
        let ideal = SettingsWindowSizing.idealContentHeight

        // A measurement that collapses to a default (or explodes because the
        // width was never constrained) would hide cards behind the scroll
        // view again, which is exactly what this guards.
        XCTAssertGreaterThan(ideal, SettingsWindowSizing.minimumHeight)
        XCTAssertLessThan(ideal, 1400)

        // A roomy screen shows everything; a short one clamps instead.
        XCTAssertEqual(SettingsWindowSizing.height(visibleScreenHeight: 5000), ideal)
        XCTAssertEqual(
            SettingsWindowSizing.height(visibleScreenHeight: 300),
            SettingsWindowSizing.minimumHeight
        )
    }

    @MainActor
    func testSettingsWindowContentMatchesTheMeasuredCardHeight() {
        KiplessSettingsOpener.open()
        defer { NSApp.windows.first(where: { $0.title == KiplessSettingsOpener.windowTitle })?.close() }

        guard let window = NSApp.windows.first(where: { $0.title == KiplessSettingsOpener.windowTitle }) else {
            return XCTFail("The Settings window was not created")
        }

        let expected = SettingsWindowSizing.height(
            visibleScreenHeight: NSScreen.main?.visibleFrame.height ?? 900
        )
        XCTAssertEqual(window.contentView?.bounds.height ?? 0, expected, accuracy: 1)
    }

    @MainActor
    func testSettingsOpenerShowsTheDedicatedSettingsWindow() {
        KiplessSettingsOpener.open()
        defer { NSApp.windows.first(where: { $0.title == KiplessSettingsOpener.windowTitle })?.close() }

        XCTAssertTrue(NSApp.windows.contains(where: { $0.title == KiplessSettingsOpener.windowTitle && $0.isVisible }))
    }

    @MainActor
    func testLoginItemsOpenerWaitsForSystemSettingsBeforeOpeningTheDeepLink() {
        let recorder = LoginItemsOpenRecorder()

        KiplessLoginItemsOpener.openLoginItems(
            launchSystemSettings: { completion in
                recorder.launchCompletion = completion
            },
            openURL: { url in
                recorder.openedURL = url
                return true
            },
            activate: { _ in }
        )

        XCTAssertNil(recorder.openedURL)

        recorder.launchCompletion?(nil)

        XCTAssertEqual(
            recorder.openedURL?.absoluteString,
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        )
    }
}

private final class LoginItemsOpenRecorder: @unchecked Sendable {
    var launchCompletion: (@Sendable (NSRunningApplication?) -> Void)?
    var openedURL: URL?
}

private final class ApprovalAlertRecorder: @unchecked Sendable {
    var texts: [String] = []
    var openCount = 0
}
