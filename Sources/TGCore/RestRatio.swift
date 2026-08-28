// TGCore — rest ratio: minutes rested per hour on screen.
//
// One number, no grade. 20-20-20 — look away for twenty seconds every twenty minutes — works out
// at three twenty-second breaks an hour, so a day that keeps the rhythm lands at about 1.0
// minute of rest per hour of screen time. That's the reference the ring is drawn against; going
// past it just fills the ring, it is never "over".
//
// Pure and deterministic: a function of a day's counters and the user's own break lengths.

import Foundation

public struct RestRatio: Equatable, Sendable {

    // MARK: - Constants

    /// Under a quarter of an hour at the machine there is nothing to divide by that wouldn't
    /// read as noise — two minutes of screen time and one break is not a ratio of 30.
    public static let minimumScreenSeconds: TimeInterval = 15 * 60
    /// Floor for the divisor, in hours. Belt and braces with the threshold above.
    public static let minimumScreenHours: Double = 0.25
    /// What keeping the 20-20-20 rhythm comes to, in minutes of rest per hour.
    public static let reference: Double = 1.0

    // MARK: - Inputs

    /// Seconds of actual rest: completed breaks plus the natural ones.
    public let restSeconds: TimeInterval
    /// Seconds of unpaused screen time the rest is measured against.
    public let screenSeconds: TimeInterval

    public init(restSeconds: TimeInterval, screenSeconds: TimeInterval) {
        self.restSeconds = max(0, restSeconds)
        self.screenSeconds = max(0, screenSeconds)
    }

    // MARK: - Derived

    /// Minutes rested per hour on screen, or `nil` when the day is too short to divide.
    /// The UI draws "—" for `nil` rather than inventing a number.
    public var minutesPerHour: Double? {
        guard screenSeconds >= Self.minimumScreenSeconds else { return nil }
        let hours = max(Self.minimumScreenHours, screenSeconds / 3600)
        return (restSeconds / 60) / hours
    }

    /// How full the breath ring is drawn, 0...1. Clamped: past the reference the ring is simply
    /// full, because a day of long walks is not a failure state that needs its own colour.
    public var progress: Double {
        guard let value = minutesPerHour, Self.reference > 0 else { return 0 }
        return min(1, max(0, value / Self.reference))
    }

    // MARK: - Building

    /// A day's rest, judged against the user's own break lengths.
    ///
    /// Natural breaks are counted as one configured short break each: we know the user walked
    /// away, but crediting the whole twenty-five-minute lunch would let one long absence claim a
    /// perfect day of rest that nobody's eyes actually got.
    public static func rest(for day: DayStats, settings: Settings) -> TimeInterval {
        day.breakTime + Double(max(0, day.breaksNatural)) * max(0, settings.shortBreakDuration)
    }

    public static func compute(for day: DayStats, settings: Settings) -> RestRatio {
        RestRatio(restSeconds: rest(for: day, settings: settings),
                  screenSeconds: day.totalScreenTime)
    }
}
