// TGCore — the per-day statistics record persisted by StatsStore.
//
// Everything here is a *fact about a calendar day*, recorded as it happens by StatsRecorder.
// Nothing is derived at read time and nothing is graded: the panel draws these numbers, it
// doesn't mark them.

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

    /// Wall-clock end of the session. Only meaningful for display — a session that spanned a
    /// pause is shorter than its span, because a call is not screen time.
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

    // MARK: Pauses
    /// Spans the engine spent paused — calls, videos, fullscreen apps, time away. Neither screen
    /// time nor rest; the timeline draws them hatched. Capped — see `maxPauses`.
    public var pauses: [IntervalRecord] = []

    // MARK: Break log
    /// When today's breaks happened and how each ended. The counters above say how many; this
    /// says where in the day. Capped — see `maxBreaks`.
    public var breaks: [BreakRecord] = []

    // MARK: Apps
    /// bundle ID → how long that app was frontmost today. Empty unless `Settings.trackAppUsage`
    /// is on. See `AppUsage.swift` for the bookkeeping.
    public var appUsage: [String: AppUsage] = [:]

    // MARK: - Init

    public init(dayKey: String) {
        self.dayKey = dayKey
    }

    // MARK: - Codable

    /// Hand-written, because the synthesized initialiser treats every non-optional property as
    /// *required* whether it has a default or not — so a single counter added in a new build
    /// would throw on an older `stats.json` and take the user's whole history with it. Every
    /// key here is optional at read time and falls back to the property's default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = (try? c.decode(String.self, forKey: .dayKey)) ?? ""
        totalScreenTime = (try? c.decode(TimeInterval.self, forKey: .totalScreenTime)) ?? 0
        longestSession = (try? c.decode(TimeInterval.self, forKey: .longestSession)) ?? 0
        sessions = (try? c.decode([SessionRecord].self, forKey: .sessions)) ?? []
        breaksCompleted = (try? c.decode(Int.self, forKey: .breaksCompleted)) ?? 0
        breakTime = (try? c.decode(TimeInterval.self, forKey: .breakTime)) ?? 0
        breaksSkipped = (try? c.decode(Int.self, forKey: .breaksSkipped)) ?? 0
        breaksNatural = (try? c.decode(Int.self, forKey: .breaksNatural)) ?? 0
        naturalBreakTime = (try? c.decode(TimeInterval.self, forKey: .naturalBreakTime)) ?? 0
        snoozesUsed = (try? c.decode(Int.self, forKey: .snoozesUsed)) ?? 0
        pauses = (try? c.decode([IntervalRecord].self, forKey: .pauses)) ?? []
        breaks = (try? c.decode([BreakRecord].self, forKey: .breaks)) ?? []
        appUsage = (try? c.decode([String: AppUsage].self, forKey: .appUsage)) ?? [:]
    }

    // MARK: - Derived

    /// A day the user actually spent at the machine. Days without data render as "—" rather
    /// than as numbers nobody produced.
    public var hasData: Bool {
        totalScreenTime > 0 || breaksCompleted > 0 || breaksSkipped > 0 || breaksNatural > 0
    }

    /// Breaks that count as rest: ones TouchGrass ran, plus ones the user took by walking away.
    public var breaksTaken: Int { breaksCompleted + breaksNatural }

    /// Sessions that ran past the configured interval — the ones the timeline draws in clay.
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

    /// Appends, evicting the *shortest* session when full: the timeline is carried by the long
    /// sessions, so the short ones are the ones we can afford to forget.
    public mutating func append(_ session: SessionRecord) {
        sessions.append(session)
        guard sessions.count > Self.maxSessions else { return }
        if let shortest = sessions.indices.min(by: { sessions[$0].duration < sessions[$1].duration }) {
            sessions.remove(at: shortest)
        }
    }

    // MARK: - Pause bookkeeping

    /// Same reasoning as `maxSessions`: a day of flickering pause reasons is pathological, not
    /// informative, and the aggregate counters live elsewhere.
    public static let maxPauses = 200

    /// Appends a paused span, evicting the *shortest* when full — the ones too small to draw.
    public mutating func appendPause(_ pause: IntervalRecord) {
        guard pause.duration > 0 else { return }
        pauses.append(pause)
        guard pauses.count > Self.maxPauses else { return }
        if let shortest = pauses.indices.min(by: { pauses[$0].duration < pauses[$1].duration }) {
            pauses.remove(at: shortest)
        }
    }

    // MARK: - Break bookkeeping

    public static let maxBreaks = 200

    /// Appends a break, dropping the *oldest* when full: unlike sessions there is no length to
    /// rank them by, and the recent end of the day is the half you're looking at.
    public mutating func appendBreak(_ record: BreakRecord) {
        breaks.append(record)
        if breaks.count > Self.maxBreaks { breaks.removeFirst(breaks.count - Self.maxBreaks) }
    }

    /// Breaks that rested the user, oldest first.
    public var restBreaks: [BreakRecord] { breaks.filter(\.isRest) }

    /// Breaks the user skipped, oldest first.
    public var skippedBreaks: [BreakRecord] { breaks.filter { $0.outcome == .skipped } }
}
