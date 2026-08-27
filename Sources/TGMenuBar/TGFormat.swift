// TGMenuBar — the app's number-to-English rules, in one place so every surface agrees.
import Foundation

/// Formatting helpers for countdowns and durations.
public enum TGFormat {

    /// Countdown clock: `16:24`, or `1:02:30` once an hour is involved.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    /// Human duration for summary rows: `30 secs`, `3 mins`, `1 hr`, `1 hr 30 mins`.
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

    /// "in 4 min" / "in 40 secs" for the wellness row.
    public static func relative(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 90 { return "in \(total) secs" }
        return "in \(Int((Double(total) / 60).rounded())) min"
    }
}
