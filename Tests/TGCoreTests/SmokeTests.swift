import XCTest
@testable import TGCore

final class SmokeTests: XCTestCase {
    func testSettingsRoundTrip() throws {
        let s = Settings()
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: data), s)
    }
}
