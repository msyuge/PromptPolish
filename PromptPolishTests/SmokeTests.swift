import XCTest
@testable import PromptPolish

final class SmokeTests: XCTestCase {
    func testBundleIdentifier() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "local.promptpolish")
    }
}
