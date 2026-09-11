import XCTest
@testable import Kipless

final class KiplessLayoutTests: XCTestCase {
    func testQuietOptionsFitWithWrappedEnglishModeCopy() {
        let contentHeight = KiplessLayout.optionsContentHeight(
            explanationLines: 2,
            modeLineCounts: [
                (title: 2, subtitle: 3),
                (title: 1, subtitle: 2)
            ]
        )

        XCTAssertLessThanOrEqual(contentHeight, KiplessLayout.sessionPanelHeight)
    }

    func testDurationPickerHasRoomForTheEnglishPresetLabel() {
        XCTAssertGreaterThanOrEqual(KiplessLayout.durationPickerWidth, 96)
    }
}
