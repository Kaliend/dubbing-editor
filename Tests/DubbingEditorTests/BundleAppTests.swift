import XCTest
@testable import DubbingEditor

final class BundleAppTests: XCTestCase {
    func testAppBundleResolvesLocalizedAlertStrings() {
        let localized = String(localized: "alert.export_docx_done", bundle: .appBundle)

        XCTAssertNotEqual(localized, "alert.export_docx_done")
        XCTAssertTrue(localized.contains("%@"))
        XCTAssertTrue(localized.contains("%d"))
    }
}
