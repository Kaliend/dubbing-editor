import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

final class SpeakerAppearanceServiceTests: XCTestCase {
    func testNormalizedSpeakerKeyCollapsesWhitespaceAndUppercases() {
        XCTAssertEqual(
            SpeakerAppearanceService.normalizedSpeakerKey("  jocelyn   "),
            "JOCELYN"
        )
        XCTAssertEqual(
            SpeakerAppearanceService.normalizedSpeakerKey("Mary   Jane"),
            "MARY JANE"
        )
        XCTAssertEqual(
            SpeakerAppearanceService.normalizedSpeakerKey("  Mary\t\n  Jane  "),
            "MARY JANE"
        )
    }

    func testDefaultPaletteAssignmentIsDeterministic() {
        let first = SpeakerAppearanceService.defaultPaletteID(for: "JOCELYN")
        let second = SpeakerAppearanceService.defaultPaletteID(for: "  jocelyn  ")

        XCTAssertEqual(first, second)
        XCTAssertNotNil(first)
    }

    func testResolvedAppearancePrefersOverride() {
        let overrides = SpeakerAppearanceService.sanitizedOverrides([
            "  Jocelyn ": SpeakerColorPaletteID.rose.rawValue
        ])

        let appearance = SpeakerAppearanceService.resolvedAppearance(
            for: "JOCELYN",
            overridesByKey: overrides
        )

        XCTAssertEqual(appearance?.paletteID, .rose)
        XCTAssertEqual(appearance?.isOverride, true)
    }
}
#endif
