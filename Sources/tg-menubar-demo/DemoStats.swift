// tg-menubar-demo — believable fake history, so the Stats tab has something to draw.
//
// A fresh checkout has no stats.json, and an empty timeline tells you nothing about whether the
// timeline is right. This seeds a deterministic run of days: a today with sessions, pauses and
// breaks spread across the working hours, a couple of quieter days behind it, and one blank day
// so the "nothing recorded" state is on screen too.
import Foundation
import TGCore

@MainActor
enum DemoStats {

    static func seed(into store: StatsStore) {
        let calendar = Calendar.current
        let today = Date()
        store.replace(todayStats(today), for: today)

        for back in 1...20 {
            guard let date = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            // Weekends and every fourth day stay blank: the empty day is a state worth seeing.
            guard weekday != 1, weekday != 7, back != 4 else { continue }
            store.replace(stats(for: date, seed: back), for: date)
        }
    }

    // MARK: - Today

    /// Hand-built to exercise every mark the timeline can draw: short stretches, two that run
    /// past the default twenty-minute interval, a stand-up, a lunch, a video, breaks taken, one
    /// skipped, and one walk away that counted as a break.
    ///
    /// The script is walked from 9am and cut off at the current time, so the "now" line always
    /// lands at the end of the day's last bar rather than in the middle of a future the demo
    /// invented.
    private static func todayStats(_ date: Date) -> DayStats {
        var stats = DayStats(dayKey: StatsStore.dayKey(for: date))
        let dayStart = Calendar.current.startOfDay(for: date)
        var cursor = dayStart.addingTimeInterval(9 * 3600)
        // TG_DEMO_DAY_END=16.75 plays the whole script out regardless of the real clock, so a
        // full day's timeline can be reviewed at ten in the morning.
        let forced = Double(ProcessInfo.processInfo.environment["TG_DEMO_DAY_END"] ?? "")
        let cutoff = forced.map { dayStart.addingTimeInterval($0 * 3600) }
            ?? min(date, dayStart.addingTimeInterval(17 * 3600))

        func room() -> TimeInterval { max(0, cutoff.timeIntervalSince(cursor)) }

        func work(_ minutes: Double) {
            let duration = min(minutes * 60, room())
            guard duration >= 60 else { cursor = cutoff; return }
            stats.append(SessionRecord(start: cursor, duration: duration))
            stats.totalScreenTime += duration
            stats.longestSession = max(stats.longestSession, duration)
            cursor = cursor.addingTimeInterval(duration)
        }

        func pause(_ minutes: Double, _ kind: PauseKind) {
            let duration = min(minutes * 60, room())
            guard duration >= 60 else { cursor = cutoff; return }
            stats.appendPause(IntervalRecord(start: cursor, duration: duration, kind: kind))
            cursor = cursor.addingTimeInterval(duration)
        }

        func rest(_ outcome: BreakOutcome, _ kind: BreakKind = .short, seconds: TimeInterval = 22) {
            guard room() > 0 else { return }
            stats.appendBreak(BreakRecord(at: cursor, kind: kind, outcome: outcome))
            switch outcome {
            case .completed:
                stats.breaksCompleted += 1
                stats.breakTime += seconds
                cursor = cursor.addingTimeInterval(seconds)
            case .skipped:
                stats.breaksSkipped += 1
            case .natural:
                stats.breaksNatural += 1
                stats.naturalBreakTime += seconds
                cursor = cursor.addingTimeInterval(seconds)
            }
        }

        work(18); rest(.completed)
        work(14); rest(.completed)
        pause(16, .meeting)
        work(22); rest(.skipped)
        work(16); rest(.completed)
        pause(48, .idle)                                  // lunch
        work(41); rest(.natural, .long, seconds: 12 * 60)
        work(19); rest(.completed)
        pause(21, .video)
        work(12)
        stats.snoozesUsed = 2

        // Eight apps so the block shows its top five and a "+3 more" line, and so both the
        // real-icon and the missing-icon paths are on screen.
        for (bundleID, name, seconds) in demoApps {
            stats.addAppUsage(bundleID: bundleID, name: name, seconds: seconds)
        }
        return stats
    }

    /// Bundle IDs that ship with macOS wherever possible, so the icons resolve on any machine.
    /// The totals add up to a little under the day's screen time — which is honest: time with
    /// nothing nameable in front belongs to no app.
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
        let dayStart = Calendar.current.startOfDay(for: date)
        var cursor = dayStart.addingTimeInterval(Double(8 + next(2)) * 3600)

        for index in 0..<(4 + next(4)) {
            let duration = TimeInterval(600 + next(2400))
            stats.append(SessionRecord(start: cursor, duration: duration))
            stats.totalScreenTime += duration
            stats.longestSession = max(stats.longestSession, duration)
            cursor = cursor.addingTimeInterval(duration)

            if index % 3 == 1 {
                let pause = TimeInterval(600 + next(1800))
                stats.appendPause(IntervalRecord(start: cursor, duration: pause,
                                                 kind: next(2) == 0 ? .meeting : .idle))
                cursor = cursor.addingTimeInterval(pause)
            } else {
                let skipped = next(4) == 0
                stats.appendBreak(BreakRecord(at: cursor, kind: .short,
                                              outcome: skipped ? .skipped : .completed))
                if skipped { stats.breaksSkipped += 1 } else { stats.breaksCompleted += 1 }
                cursor = cursor.addingTimeInterval(120)
            }
        }
        stats.breakTime = TimeInterval(stats.breaksCompleted) * 45
        stats.breaksNatural = next(3)
        stats.naturalBreakTime = TimeInterval(stats.breaksNatural) * 600
        stats.snoozesUsed = next(4)
        return stats
    }
}
