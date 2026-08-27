// TGCore — the per-day statistics record persisted by StatsStore.
//
// Everything here is a *fact about a calendar day*, recorded as it happens by StatsRecorder.
// Nothing is derived at read time except `stats`, which StatsStore caches on every write
// so the UI can render a month of gauges without recomputing ninety stats per frame.

import Foundation

// MARK: - Session

/// One uninterrupted stretch of screen time: from the moment the user started working to the
/// break (or midnight) that ended it.
///
/// `duration` counts only *unpaused* seconds, so a meeting in the middle of a session shortens
/// it without splitting it — a call is not a rest for your eyes, but it isn't screen time we're
/// asking the user to answer for either.
public struct SessionRecord: Codable, Equatable, Sendable, Hashable {
    public var start: Date
    public var duration: TimeInterval

    public init(start: Date, duration: TimeInterval) {
        self.start = start
        self.duration = max(0, duration)
    }

    /// Wall-clock end of the session. Only meaningful for display; the stat uses `duration`.
    public var end: Date { start.addingTimeInterval(duration) }
}

// MARK: - Day

/// One day's worth of stats. Codable, and every field has a default so a stats.json written by
/// an older build still decodes after new counters are added.
public struct DayStats: Codable, Equatable, Sendable {

    /// `yyyy-MM-dd` in the user's calendar. Stored as well as keyed so a decoded value is
    /// self-describing.
    public var dayKey: String

    // MARK: Screen time
    /// Total unpaused screen seconds accrued today.
    public var totalScreenTime: TimeInterval = 0
    /// The longest single session today, including the one currently in progress.
    public var longestSession: TimeInterval = 0
    /// Finalised (and one in-progress) sessions, oldest first. Capped — see `maxSessions`.
    public var sessions: [SessionRecord] = []

    // MARK: Breaks
    /// Breaks TouchGrass ran that reached the end (or were ended past the allowed fraction).
    public var breaksCompleted: Int = 0
    /// Total seconds spent in those breaks.
    public var breakTime: TimeInterval = 0
    /// Breaks the user skipped outright.
    public var breaksSkipped: Int = 0
    /// Times the user was away long enough that the engine counted it as a break already taken.
    public var breaksNatural: Int = 0
    /// Total seconds spent away during those natural breaks.
    public var naturalBreakTime: TimeInterval = 0
    /// "+1m / +5m / +15m" spent out of the snooze budget.
    public var snoozesUsed: Int = 0

    // MARK: stat
    /// 0–100, recomputed by `StatsStore` on every write. Cached rather than computed so the
    /// calendar can draw a whole month without re-running the statr per cell per frame.
    public var stats: Int = Stats.perfect

    // MARK: - Init

    public init(dayKey: String) {
        self.dayKey = dayKey
    }

    // MARK: - Derived

    /// A day the user actually spent at the machine. Days without data render as "--" rather
    /// than as a perfect 100 they didn't earn.
    public var hasData: Bool {
        totalScreenTime > 0 || breaksCompleted > 0 || breaksSkipped > 0 || breaksNatural > 0
    }

    /// Breaks that count as rest: ones TouchGrass ran, plus ones the user took by walking away.
    public var breaksTaken: Int { breaksCompleted + breaksNatural }

    /// Sessions that ran past the configured interval — the "you sat too long" count.
    public func sessionsOverrunning(_ interval: TimeInterval) -> Int {
        guard interval > 0 else { return 0 }
        return sessions.filter { $0.duration > interval }.count
    }

    // MARK: - Session bookkeeping

    /// A day of thirty-second sessions is pathological, not informative; cap the array so one
    /// bad day can't grow stats.json without bound. The aggregate counters are kept separately,
    /// so dropping records never falsifies total screen time.
    public static let maxSessions = 250

    /// Records `duration` against the session that began at `start`, appending it if it's new.
    public mutating func updateSession(start: Date, duration: TimeInterval) {
        if let index = sessions.lastIndex(where: { $0.start == start }) {
            sessions[index].duration = max(0, duration)
        } else {
            append(SessionRecord(start: start, duration: duration))
        }
    }

    public mutating func removeSession(start: Date) {
        sessions.removeAll { $0.start == start }
    }

    /// Appends, evicting the *shortest* session when full: the stat is driven by long
    /// sessions, so the short ones are the ones we can afford to forget.
    public mutating func append(_ session: SessionRecord) {
        sessions.append(session)
        guard sessions.count > Self.maxSessions else { return }
        if let shortest = sessions.indices.min(by: { sessions[$0].duration < sessions[$1].duration }) {
            sessions.remove(at: shortest)
        }
    }
}
