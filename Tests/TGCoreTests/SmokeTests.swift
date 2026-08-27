import Testing
import Foundation
@testable import TGCore

@Test func settingsRoundTrip() throws {
    let s = Settings()
    let data = try JSONEncoder().encode(s)
    #expect(try JSONDecoder().decode(Settings.self, from: data) == s)
}
