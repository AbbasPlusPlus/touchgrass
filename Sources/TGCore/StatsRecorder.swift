// TGCore — StatsRecorder: turns the engine's phase and events into a day of stats.
//
// The engine knows nothing about statistics and stays that way; this object listens to the
// same `phase` / `events` surface the UI listens to and writes what it hears into StatsStore.
//
// Two jobs:
//   1. Clock screen time. Seconds accrue while the engine is `.running` / `.preBreak` /
//      `.waitingForActivityToStop` and stop dead while it's paused, in a break, or stopped.
//   2. Count breaks — completed, skipped, natural (an away-reset), and snoozes — and log where
//      in the day each one landed.
//   3. Record the spans the engine spent paused, so the timeline can draw the calls and the
//      walks away as what they were: neither screen time nor rest.
//   4. Attribute those seconds to whichever app was in front (`noteFrontmostApp`), when the
//      user leaves `Settings.trackAppUsage` on. The frontmost app is public information, so
//      this costs no permission and no poll — the host pushes changes as they happen.
//
// A *session* is the stretch between rests. Pausing for a meeting doesn't end one — a call is
// not a rest for your eyes — so a paused stretch merely stops the clock. Sessions end when a
// break starts, when the engine decides the user was away long enough to count as a break, when
// TouchGrass stops, and at midnight, which splits the session across the two days it spans.
//
// All timing is wall-clock: every accrual measures `clock.now()` against the last accrual point,
// so a tick that arrives after a lid-closed hour accounts for exactly the seconds that were
// actually spent looking at the screen (none of them).

import Foundation
import Combine

@MainActor
public final class StatsRecorder {

    // MARK: - Dependencies

    private let engine: BreakEngine
    private let store: StatsStore
    private let clock: Clock
    private let calendar: Calendar
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - State

    private var running = false
    /// Whether the engine's current phase counts as screen time.
    private var accruing = false
    /// Wall-clock stamp of the last accrual. `nil` until `start()`.
    private var lastAt: Date?
    /// Start of the session in progress, `nil` when none is open.
    private var sessionStart: Date?
    /// Screen seconds accrued into the open session so far.
    private var sessionAccrued: TimeInterval = 0
    /// When the break on screen began, so its real length can be recorded when it ends.
    private var breakStartedAt: Date?
    /// Start of the paused span in progress, `nil` when the engine isn't paused.
    private var pauseStart: Date?
    /// Why that span is paused. Kept beside `pauseStart` so a change of reason mid-pause closes
    /// one span and opens another rather than mislabelling the whole thing.
    private var pauseKind: PauseKind?
    /// The app currently in front, as last reported by the host. `nil` means "nobody we can
    /// name" — those seconds still count as screen time, they just belong to no app.
    private var frontmostBundleID: String?
    private var frontmostName: String?

    // MARK: - Init

    public init(
        engine: BreakEngine,
        store: StatsStore,
        clock: Clock = SystemClock(),
        calendar: Calendar = .current
    ) {
        self.engine = engine
        self.store = store
        self.clock = clock
        self.calendar = calendar

        engine.$phase
            .sink { [weak self] phase in self?.phaseChanged(to: phase) }
            .store(in: &cancellables)
        engine.events
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    public func start() {
        let now = clock.now()
        running = true
        lastAt = now
        accruing = Self.accruesScreenTime(engine.phase)
        if accruing { openSession(at: now) }
    }

    public func stop() {
        let now = clock.now()
        accrue(upTo: now)
        finalizeSession()
        closePause(at: now)
        accruing = false
        running = false
        store.flush()
    }

    /// Called by the app's 1 Hz heartbeat, right after `BreakEngine.tick()`.
    public func tick() {
        accrue(upTo: clock.now())
    }

    // MARK: - Frontmost app

    /// Tells the recorder which app is in front. Pushed by the host (`ActivityMonitor`) on
    /// `NSWorkspace.didActivateApplicationNotification`; nothing polls.
    ///
    /// The seconds banked so far are credited to the *outgoing* app before the switch, so an
    /// app that was in front for a fraction of a tick doesn't collect the whole tick.
    public func noteFrontmostApp(bundleID: String?, name: String?) {
        guard bundleID != frontmostBundleID || name != frontmostName else { return }
        if running { accrue(upTo: clock.now()) }
        frontmostBundleID = bundleID
        frontmostName = name
    }

    // MARK: - Phase

    /// Screen time is the time the engine is counting *toward* a break — everything else is
    /// either rest (a break) or time we've deliberately stopped judging (a pause).
    static func accruesScreenTime(_ phase: EnginePhase) -> Bool {
        switch phase {
        case .running, .preBreak, .waitingForActivityToStop: return true
        case .stopped, .inBreak, .paused: return false
        }
    }

    private func phaseChanged(to phase: EnginePhase) {
        guard running else { return }
        let now = clock.now()
        // Bank the seconds since the last accrual against the phase they were actually spent in,
        // *before* switching over.
        accrue(upTo: now)

        accruing = Self.accruesScreenTime(phase)
        if phase == .stopped { finalizeSession() }
        if accruing { openSession(at: now) }
    }

    // MARK: - Events

    private func handle(_ event: EngineEvent) {
        guard running else { return }
        let now = clock.now()
        switch event {
        case .breakStarted:
            accrue(upTo: now)
            accruing = false
            finalizeSession()
            breakStartedAt = now

        case .breakEnded(let kind, let completed):
            // How long the break was actually on screen, not how long it was scheduled for —
            // "End break" early should not be able to claim the full three minutes.
            let startedAt = breakStartedAt
            let elapsed = startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
            breakStartedAt = nil
            guard completed else { return }   // skip / snooze are counted from their own events
            let at = startedAt ?? now
            store.mutate(at) { day in
                day.breaksCompleted += 1
                day.breakTime += elapsed
                day.appendBreak(BreakRecord(at: at, kind: kind, outcome: .completed))
            }

        case .skipped(let kind):
            store.mutate(now) { day in
                day.breaksSkipped += 1
                day.appendBreak(BreakRecord(at: now, kind: kind, outcome: .skipped))
            }

        case .snoozed:
            store.mutate(now) { $0.snoozesUsed += 1 }

        case .awayDecision(let resetTimer, let awayFor):
            // Only a reset is a break; a short away is just a coffee refill mid-session.
            guard resetTimer else { return }
            accrue(upTo: now)
            finalizeSession()
            store.mutate(now) { day in
                day.breaksNatural += 1
                day.naturalBreakTime += awayFor
                // Filed as short: what the user got was a rest, and the cadence of long breaks
                // is TouchGrass's bookkeeping, not something a walk to the kettle belongs to.
                day.appendBreak(BreakRecord(at: now, kind: .short, outcome: .natural))
            }

        case .paused(let reasons):
            openPause(at: now, kind: PauseKind.primary(of: reasons) ?? .other)

        case .resumed:
            closePause(at: now)

        case .preBreakWarning, .preBreakCountdown, .breakTick,
             .wellnessReminder, .customReminder:
            break
        }
    }

    // MARK: - Screen time

    /// Bank every second between the last accrual point and `now`, splitting at midnight so a
    /// session that runs past twelve lands in both days rather than all in one.
    private func accrue(upTo now: Date) {
        defer { lastAt = now }
        guard running, accruing, let last = lastAt, now > last else { return }

        var cursor = last
        while cursor < now {
            let dayStart = calendar.startOfDay(for: cursor)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now
            let chunkEnd = min(nextDay, now)
            let delta = chunkEnd.timeIntervalSince(cursor)
            guard delta > 0 else { break }

            // Midnight: close the session on the day it belonged to and open a fresh one, so a
            // stretch that runs past twelve is two sessions of the right length rather than one
            // double-length session filed under both days.
            if let start = sessionStart, !calendar.isDate(start, inSameDayAs: cursor) {
                finalizeSession()
            }
            openSession(at: cursor)
            sessionAccrued += delta
            let start = sessionStart ?? cursor
            let accrued = sessionAccrued
            // Whoever is in front gets this chunk. Because the chunking is what splits the
            // accrual at midnight, per-app time lands on the right day for free.
            let app = trackedApp
            store.mutate(cursor) { day in
                day.totalScreenTime += delta
                day.longestSession = max(day.longestSession, accrued)
                day.updateSession(start: start, duration: accrued)
                if let app {
                    day.addAppUsage(bundleID: app.bundleID, name: app.name, seconds: delta)
                }
            }

            cursor = chunkEnd
        }
    }

    /// The app this accrual should be credited to, or `nil` when there is nobody to credit —
    /// either nothing nameable is in front, or the user turned app tracking off.
    private var trackedApp: (bundleID: String, name: String)? {
        guard store.settings.trackAppUsage, let bundleID = frontmostBundleID, !bundleID.isEmpty else { return nil }
        return (bundleID, frontmostName ?? bundleID)
    }

    // MARK: - Pauses

    /// Opens a paused span, or re-labels the open one by closing it and starting another: the
    /// engine re-emits `.paused` whenever the reason set changes, and a call that turns into a
    /// walk away is two different facts about the day.
    private func openPause(at date: Date, kind: PauseKind) {
        guard pauseKind != kind else { return }
        closePause(at: date)
        pauseStart = date
        pauseKind = kind
    }

    /// Banks the open span, splitting it at midnight the way screen time is split so a call that
    /// runs past twelve lands in both days.
    private func closePause(at end: Date) {
        guard let start = pauseStart, let kind = pauseKind else { return }
        pauseStart = nil
        pauseKind = nil

        var cursor = start
        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? end
            let chunkEnd = min(nextDay, end)
            let delta = chunkEnd.timeIntervalSince(cursor)
            guard delta > 0 else { break }
            // A sub-second pause is a flicker between two detector updates, not a span of the
            // day; recording it would only cost a slot in the capped array.
            if delta >= 1 {
                let record = IntervalRecord(start: cursor, duration: delta, kind: kind)
                store.mutate(cursor) { $0.appendPause(record) }
            }
            cursor = chunkEnd
        }
    }

    // MARK: - Sessions

    private func openSession(at date: Date) {
        guard sessionStart == nil else { return }
        sessionStart = date
        sessionAccrued = 0
    }

    private func finalizeSession() {
        guard let start = sessionStart else { return }
        let accrued = sessionAccrued
        sessionStart = nil
        sessionAccrued = 0
        store.mutate(start) { day in
            // A session that never accrued a whole second is an artefact of a phase flicker,
            // not a stretch of work — don't leave it in the record.
            if accrued < 1 {
                day.removeSession(start: start)
            } else {
                day.updateSession(start: start, duration: accrued)
            }
        }
    }
}
