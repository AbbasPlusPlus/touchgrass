// TGCore — where the stats live: one JSON file, keyed by day.
//
// A file per day would mean ~365 stat() calls to draw one month of the calendar; a single
// `stats.json` holding a dayKey → DayStats map is a few kilobytes a year and loads in one read.
//
// Writes are coalesced. Screen time accrues every second, so saving on every mutation would
// rewrite the file 3,600 times an hour for no benefit; `scheduleSave()` batches a burst of
// mutations into one atomic write half a minute later, and `flush()` forces one at shutdown.

import Foundation
import Combine

@MainActor
public final class StatsStore: ObservableObject {

    // MARK: - State

    /// dayKey (`yyyy-MM-dd`) → that day's record. Read-only from outside; mutate via `mutate`.
    @Published public private(set) var days: [String: DayStats] = [:]

    /// The statr needs the user's own break interval, so the store keeps a copy of settings and
    /// restats every day when the interval changes — otherwise yesterday's gauge would still be
    /// judged against yesterday's setting.
    public var settings: Settings {
        didSet {
            guard oldValue.shortBreakInterval != settings.shortBreakInterval else { return }
            restatAll()
        }
    }

    private let url: URL
    private var saveScheduled = false

    /// Screen time is dirty every second, so this is what sets the write rate: half a minute
    /// means one small atomic write a minute-ish rather than hundreds. A crash costs the last
    /// half-minute of screen time; a clean exit costs nothing, because the app calls `flush()`.
    static let saveDebounce: TimeInterval = 30
    /// Days older than this are dropped on load. A year of history is more than the UI shows.
    static let retentionDays = 400

    // MARK: - Init

    public init(settings: Settings = Settings(), url: URL? = nil) {
        self.settings = settings
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TouchGrass", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = url ?? directory.appendingPathComponent("stats.json")
        self.days = Self.load(from: self.url)
    }

    // MARK: - Day keys

    /// `yyyy-MM-dd` in the current calendar. Built from date components rather than a
    /// `DateFormatter` so it can't drift with the user's locale or a formatter's time zone.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: - Reading

    /// The record for `date`'s day — an empty one if nothing was ever recorded then.
    public func stats(for date: Date) -> DayStats {
        days[Self.dayKey(for: date)] ?? DayStats(dayKey: Self.dayKey(for: date))
    }

    public func today(_ now: Date = Date()) -> DayStats { stats(for: now) }

    /// True when `date`'s day has anything worth drawing.
    public func hasData(for date: Date) -> Bool { stats(for: date).hasData }

    // MARK: - Writing

    /// The single write path: mutate `date`'s record, restat it, and queue a save.
    public func mutate(_ date: Date, _ body: (inout DayStats) -> Void) {
        let key = Self.dayKey(for: date)
        var day = days[key] ?? DayStats(dayKey: key)
        body(&day)
        day.dayKey = key
        day.stats = Stats.stat(for: day, settings: settings)
        days[key] = day
        scheduleSave()
    }

    /// Drops a whole record in place — used by the demo to seed a believable month and by
    /// anything that needs to import history wholesale.
    public func replace(_ stats: DayStats, for date: Date) {
        mutate(date) { $0 = stats }
    }

    public func removeAll() {
        days.removeAll()
        scheduleSave()
    }

    // MARK: - Persistence

    /// Write now rather than on the debounce. Call before the app goes away.
    public func flush() {
        saveScheduled = false
        save()
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDebounce) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.saveScheduled else { return }
                self.saveScheduled = false
                self.save()
            }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Archive(version: Archive.currentVersion, days: days)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// A corrupt or unreadable file is not worth an error dialog — stats are a nicety, and
    /// starting from an empty month is a better answer than refusing to open the panel.
    private static func load(from url: URL) -> [String: DayStats] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(Archive.self, from: data) else { return [:] }
        return prune(archive.days)
    }

    /// Keeps the newest `retentionDays` recorded days.
    ///
    /// Measured against the newest key in the file rather than against `Date()`: pruning by
    /// wall clock would quietly delete a returning user's whole history the first time they
    /// opened the app after a long break, which is the moment they'd most want to see it.
    /// `yyyy-MM-dd` sorts lexicographically the same way the days run, so this is a date sort.
    private static func prune(_ days: [String: DayStats]) -> [String: DayStats] {
        guard days.count > retentionDays else { return days }
        let keep = Set(days.keys.sorted().suffix(retentionDays))
        return days.filter { keep.contains($0.key) }
    }

    // MARK: - Scoring

    private func restatAll() {
        for (key, day) in days {
            var updated = day
            updated.stats = Stats.stat(for: day, settings: settings)
            days[key] = updated
        }
        scheduleSave()
    }

    // MARK: - File format

    private struct Archive: Codable {
        static let currentVersion = 1
        var version: Int
        var days: [String: DayStats]
    }
}
