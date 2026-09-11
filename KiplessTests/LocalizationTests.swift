import Foundation
import XCTest
@testable import Kipless

final class LocalizationTests: XCTestCase {
    func testLocalizationResourcesUseSemanticKeys() {
        let keys = KiplessStrings.allResources.map(\.key)

        XCTAssertEqual(keys.count, Set(keys).count)
        XCTAssertTrue(keys.allSatisfy { $0.contains(".") })
        XCTAssertFalse(keys.contains("Keep Mac Awake"))
        XCTAssertFalse(keys.contains("Keep Mac + Display Awake"))
    }

    func testCoreCopyHasEnglishFallbackValues() {
        XCTAssertEqual(
            String(localized: KiplessStrings.modeSystemTitle),
            "Let the screen turn off"
        )
        XCTAssertEqual(
            String(localized: KiplessStrings.modeDisplayTitle),
            "Keep the screen on"
        )
        XCTAssertEqual(
            String(localized: KiplessStrings.modeExplanation),
            "Your Mac stays awake in both options."
        )
    }
}
