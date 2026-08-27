// TGMenuBar — the app's number-to-English rules, in one place so every surface agrees.
import Foundation

/// Formatting helpers for countdowns and durations.
///
/// House rule: **the menu bar never shows seconds.** A `mm:ss` ticking away in the corner of
/// the screen is a low-grade anxiety machine, so the status item counts down in whole minutes
/// (`24m`) and rounds up, and prose countdowns read `22 min`. Seconds survive in exactly two
/// places: the quick panel's big countdown and the break itself — surfaces you have chosen to
/// look at — plus configured durations, where "30 secs" is a fact about a setting, not a clock.
public enum TGFormat {

    // MARK: - Countdowns

    /// Status item countdown: `24m`, `1m`, `1h 5m`. Rounds *up*, so it never reads `0m`
    /// and never shows seconds.
    public static func menuBar(_ seconds: TimeInterval) -> String {
        let total = ceilMinutes(seconds)
        if total < 60 { return "\(total)m" }
        let hours = total / 60
        let rest = total % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// Prose countdown: `22 min`, `1 min`, `1 hr 5 min`. Rounds up; never reads `0 min`.
    public static func minutes(_ seconds: TimeInterval) -> String {
        let total = ceilMinutes(seconds)
        if total < 60 { return "\(total) min" }
        let hours = total / 60
        let rest = total % 60
        let base = "\(hours) \(hours == 1 ? "hr" : "hrs")"
        return rest == 0 ? base : "\(base) \(rest) min"
    }

    /// Clock with seconds: `0:24`, `22:51`, `1:02:30`.
    ///
    /// Only for the quick panel countdown and the break overlay. Never the status item.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Elapsed

    /// Time already spent, minute-granular: `7 mins`, `1 min`, `1 hr 12 mins`.
    /// Rounds *down* — claiming a minute you haven't spent would be a lie.
    public static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds)) / 60
        if total == 0 { return "Under a minute" }
        if total < 60 { return "\(total) \(total == 1 ? "min" : "mins")" }
        let hours = total / 60
        let rest = total % 60
        let base = "\(hours) \(hours == 1 ? "hr" : "hrs")"
        return rest == 0 ? base : "\(base) \(rest) \(rest == 1 ? "min" : "mins")"
    }

    /// Time already spent, compact enough for a column: `1h 12m`, `8m`, `<1m`.
    ///
    /// Rounds *down* like `elapsed`, and says `<1m` rather than `0m` — an app you glanced at
    /// for twenty seconds should read as a glance, not as a measurement or as a whole minute.
    public static func compactElapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds)) / 60
        if total == 0 { return "<1m" }
        if total < 60 { return "\(total)m" }
        let hours = total / 60
        let rest = total % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    // MARK: - Configured durations

    /// Human duration for summary rows: `30 secs`, `3 mins`, `1 hr`, `1 hr 30 mins`.
    ///
    /// This describes a *setting* ("a short break is 30 secs"), not a countdown, so seconds
    /// are allowed — otherwise a 30-second break would have to lie about being a minute.
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) \(total == 1 ? "sec" : "secs")" }
        let minutes = total / 60
        let leftoverSeconds = total % 60
        if minutes < 60 {
            let base = "\(minutes) \(minutes == 1 ? "min" : "mins")"
            return leftoverSeconds == 0 ? base : "\(base) \(leftoverSeconds) secs"
        }
        let hours = minutes / 60
        let leftoverMinutes = minutes % 60
        let base = "\(hours) \(hours == 1 ? "hr" : "hrs")"
        return leftoverMinutes == 0 ? base : "\(base) \(leftoverMinutes) mins"
    }

    /// Compact form for pickers and pill labels: `20 min`, `30 sec`.
    public static func compact(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) sec" }
        if total % 60 == 0 { return "\(total / 60) min" }
        return "\(total / 60) min \(total % 60) sec"
    }

    // MARK: - Misc

    /// "1st", "2nd", "3rd", "4th" — for "every 3rd break is a long one".
    public static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11, _), (12, _), (13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    // MARK: - Private

    /// Whole minutes, rounded up, floored at 1: a countdown that still has time left should
    /// never read zero.
    private static func ceilMinutes(_ seconds: TimeInterval) -> Int {
        max(1, Int((max(0, seconds) / 60).rounded(.up)))
    }
}
