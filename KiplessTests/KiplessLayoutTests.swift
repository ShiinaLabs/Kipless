import XCTest
@testable import Kipless

final class KiplessLayoutTests: XCTestCase {
    func testThreeModeRowsHaveIntentionalBreathingRoom() {
        XCTAssertEqual(KiplessLayout.modeOptionVerticalPadding, 4)
    }

    func testDurationPickerHasRoomForTheEnglishPresetLabel() {
        XCTAssertGreaterThanOrEqual(KiplessLayout.durationPickerWidth, 96)
    }

    func testIndefiniteDurationUsesTheIndefinitePresentation() {
        let presentation = WakeControlPresentation(duration: .indefinite, isActive: false)

        XCTAssertEqual(presentation.layout, .indefinite)
    }

    func testTimedDurationUsesTheTimedPresentation() {
        let presentation = WakeControlPresentation(duration: .minutes30, isActive: false)

        XCTAssertEqual(presentation.layout, .timed)
    }

    func testActiveSessionUsesStopAction() {
        let presentation = WakeControlPresentation(duration: .indefinite, isActive: true)

        XCTAssertEqual(presentation.action, .stop)
    }

    func testInactiveSessionUsesStartAction() {
        let presentation = WakeControlPresentation(duration: .minutes30, isActive: false)

        XCTAssertEqual(presentation.action, .start)
    }

    func testIndefiniteControlUsesCompactInlineActionLayout() {
        let layout = IndefiniteControlLayout.compact

        XCTAssertEqual(layout.actionPlacement, .inline)
        XCTAssertGreaterThanOrEqual(layout.infinityFontSize, 80)
    }

    func testIndefiniteParticlesTrailMovesLeftAndStaysVisible() {
        let initial = IndefiniteParticleMotion.particles(
            at: IndefiniteParticleMotion.cycleDuration * 0.10
        )
        let later = IndefiniteParticleMotion.particles(
            at: IndefiniteParticleMotion.cycleDuration * 0.20
        )

        XCTAssertEqual(initial.count, later.count)
        XCTAssertGreaterThan(initial[0].progress, later[0].progress)
        XCTAssertGreaterThan(later[0].opacity, 0.15)
    }

    func testIndefiniteParticleTrailIsOpticallyLowered() {
        XCTAssertGreaterThanOrEqual(
            IndefiniteControlLayout.compact.particleVerticalOffset,
            5
        )
    }

    func testOptionsPanelIsSlightlyWiderThanSessionPanel() {
        XCTAssertEqual(KiplessLayout.sessionPanelWidth, 180)
        XCTAssertEqual(KiplessLayout.optionsPanelWidth, 204)
        XCTAssertEqual(
            KiplessLayout.sessionPanelWidth + KiplessLayout.optionsPanelWidth,
            384
        )
        XCTAssertEqual(
            KiplessLayout.optionsPanelWidth - KiplessLayout.sessionPanelWidth,
            24
        )
    }
}
