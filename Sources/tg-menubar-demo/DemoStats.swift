// tg-menubar-demo — believable fake history, so the Stats tab has something to draw.
//
// A fresh checkout has no stats.json, and an empty gauge tells you nothing about whether the
// gauge is right. This seeds a deterministic month-and-a-half: a today worth 62, weekdays with
// varying stats, and empty weekends so the calendar's "no data" state is on screen too.
import Foundation
import TGCore

@MainActor
enum DemoStats {

    static func seed(into store: StatsStore) {
        let calendar = Calendar.current
        let today = Date()
        store.replace(todayStats(today), for: today)

        for back in 1...75 {
            guard let date = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            // Weekends and the odd day off stay blank, which is what the dimmed cells are for.
            guard weekday != 1, weekday != 7, back % 11 != 0 else { continue }
            store.replace(stats(for: date, seed: back), for: date)
        }
    }

    // MARK: - Today

    /// Hand-tuned to land on 62 with the default 20-minute interval: five sessions, three of
    /// which overran, four breaks taken out of five, two snoozes.
    private static func todayStats(_ date: Date) -> DayStats {
        var stats = DayStats(dayKey: StatsStore.dayKey(for: date))
        var start = Calendar.current.startOfDay(for: date).addingTimeInterval(9 * 3600)
        for duration in [1500.0, 2100.0, 1200.0, 900.0, 2000.0] {
            stats.append(SessionRecord(start: start, duration: duration))
            stats.totalScreenTime += duration
            stats.longestSession = max(stats.longestSession, duration)
            start = start.addingTimeInterval(duration + 240)
        }
        // Eight apps so the card shows its top five and a "+3 more" line, and so both the
        // real-icon and the missing-icon paths are on screen.
        for (bundleID, name, seconds) in demoApps {
            stats.addAppUsage(bundleID: bundleID, name: name, seconds: seconds)
        }
        stats.breaksCompleted = 3
        stats.breakTime = 240
        stats.breaksNatural = 1
        stats.naturalBreakTime = 1500
        stats.breaksSkipped = 1
        stats.snoozesUsed = 2
        return stats
    }

    /// Bundle IDs that ship with macOS wherever possible, so the icons resolve on any machine.
    /// The totals add up to a little under the day's 7,700 seconds of screen time — which is
    /// honest: time with nothing nameable in front belongs to no app.
    private static let demoApps: [(String, String, TimeInterval)] = [
        ("com.apple.Safari", "Safari", 4_350),
        ("com.apple.dt.Xcode", "Xcode", 1_620),
        ("com.apple.Terminal", "Terminal", 940),
        ("com.tinyspeck.slackmacgap", "Slack", 520),
        ("com.apple.mail", "Mail", 310),
        ("com.apple.Notes", "Notes", 180),
        ("com.apple.Music", "Music", 95),
        ("com.apple.Preview", "Preview", 40),
    ]

    // MARK: - History

    private static func stats(for date: Date, seed: Int) -> DayStats {
        var rng = UInt64(truncatingIfNeeded: seed)
        func next(_ upper: Int) -> Int {
            rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((rng >> 33) % UInt64(max(1, upper)))
        }

        var stats = DayStats(dayKey: StatsStore.dayKey(for: date))
        var start = Calendar.current.startOfDay(for: date).addingTimeInterval(9 * 3600)
        for _ in 0..<(4 + next(4)) {
            let duration = TimeInterval(600 + next(2100))
            stats.append(SessionRecord(start: start, duration: duration))
            stats.totalScreenTime += duration
            stats.longestSession = max(stats.longestSession, duration)
            start = start.addingTimeInterval(duration + 300)
        }
        stats.breaksCompleted = next(5)
        stats.breakTime = TimeInterval(stats.breaksCompleted) * 45
        stats.breaksNatural = next(4)
        stats.naturalBreakTime = TimeInterval(stats.breaksNatural) * 600
        stats.breaksSkipped = next(3)
        stats.snoozesUsed = next(4)
        return stats
    }
}
