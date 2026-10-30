import XCTest

final class ScaffoldTests: XCTestCase {
    func testBundleIdentifier() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "dev.heybeaux.earbud")
    }
}
