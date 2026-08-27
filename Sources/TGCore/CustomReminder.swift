// TGCore — a user-defined wellness reminder: "drink water", "stretch", "eye drops", anything.
//
// Custom reminders ride the same real-time clock as blink/posture (see WellnessScheduler): they
// keep counting through meetings and videos, and only freeze while a break overlay is on screen.

import Foundation

public struct CustomReminder: Codable, Equatable, Sendable, Hashable, Identifiable {

    public var id: UUID
    /// What the nudge says. Empty falls back to `defaultTitle`.
    public var title: String
    /// SF Symbol name. Unknown/empty falls back to `defaultSymbol`.
    public var symbol: String
    /// Real-time seconds between nudges.
    public var interval: TimeInterval
    public var enabled: Bool

    public static let defaultTitle = "Reminder"
    public static let defaultSymbol = "sparkles"

    public init(id: UUID = UUID(),
                title: String,
                symbol: String = CustomReminder.defaultSymbol,
                interval: TimeInterval = 45 * 60,
                enabled: Bool = false) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.interval = interval
        self.enabled = enabled
    }

    // MARK: - Display

    /// Never empty — the overlay always has something to draw.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultTitle : trimmed
    }

    public var displaySymbol: String {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultSymbol : trimmed
    }

    /// A reminder only fires when it's on and has a real interval.
    public var isSchedulable: Bool { enabled && interval > 0 }
}
