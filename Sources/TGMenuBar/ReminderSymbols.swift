// TGMenuBar — the curated glyph vocabulary for custom reminders.
//
// A grid of sixteen, not a symbol browser: every one of these reads at 46 pt on a break-screen
// nudge, and picking from a small set is faster than typing an SF Symbol name from memory.
import Foundation
import TGCore

enum ReminderSymbols {

    static let all: [String] = [
        "drop.fill",
        "figure.walk",
        "eye",
        "eyedropper",
        "cup.and.saucer.fill",
        "leaf",
        "lungs.fill",
        "hands.and.sparkles.fill",
        "figure.cooldown",
        "sun.max",
        "pills.fill",
        "heart.fill",
        "bolt.heart",
        "face.smiling",
        "wind",
        "sparkles",
    ]

    /// Three disabled examples, shown once on first run so the feature explains itself.
    static func examples() -> [CustomReminder] {
        [
            CustomReminder(title: "Drink water", symbol: "drop.fill", interval: 45 * 60, enabled: false),
            CustomReminder(title: "Stretch", symbol: "figure.cooldown", interval: 20 * 60, enabled: false),
            CustomReminder(title: "Eye drops", symbol: "eyedropper", interval: 2 * 3600, enabled: false),
        ]
    }

    /// Intervals offered in the row menu: 5 minutes to 4 hours.
    static let intervals: [TimeInterval] = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240].map { $0 * 60 }

    static func intervalLabel(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}
