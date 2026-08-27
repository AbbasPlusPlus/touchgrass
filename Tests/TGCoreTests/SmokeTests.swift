import Testing
import Foundation
@testable import TGCore

@Test func settingsRoundTrip() throws {
    let s = Settings()
    let data = try JSONEncoder().encode(s)
    #expect(try JSONDecoder().decode(Settings.self, from: data) == s)
}

@Test @MainActor func settingsLoadToleratesMissingKeys() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tg-settings-\(UUID().uuidString).json")
    try Data(#"{"shortBreakInterval": 1500, "enforcement": "hardcore"}"#.utf8).write(to: url)
    let s = SettingsStore.load(from: url)
    #expect(s.shortBreakInterval == 1500)
    #expect(s.enforcement == .hardcore)
    #expect(s.snoozesPerDay == Settings().snoozesPerDay)
}
