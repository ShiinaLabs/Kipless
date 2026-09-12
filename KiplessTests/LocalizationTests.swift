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
            "System"
        )
        XCTAssertEqual(
            String(localized: KiplessStrings.modeDisplayTitle),
            "Display"
        )
        XCTAssertEqual(
            String(localized: KiplessStrings.modeExplanation),
            "Choose how your Mac stays awake."
        )
        XCTAssertEqual(
            String(localized: KiplessStrings.modeClosedLidTitle),
            "Closed Lid"
        )
    }

    func testIndefinitePresentationCopyHasEnglishFallbackValues() {
        XCTAssertEqual(
            String(localized: KiplessStrings.sessionIndefiniteIdle),
            "Until stopped"
        )
        XCTAssertEqual(
            String(localized: KiplessStrings.sessionIndefiniteActive),
            "Keeping awake"
        )
    }
}
