// TGCore — BreakEngine: the break state machine.
//
// Contract: @MainActor ObservableObject. Driven by `tick()` (called ~1×/s by the app) plus
// commands from UI and signal updates from detectors. Emits EngineEvents; never touches UI.
//
// Design notes
// ------------
// * All timing is wall-clock: every `tick()` measures `clock.now() - lastTickAt` and applies that
//   delta. A tick that arrives after 30 minutes of sleep therefore accounts for 30 minutes, and the
//   engine never depends on ticks arriving at any particular rate.
// * `phase` is *derived*, never assigned ad-hoc: the engine keeps a small canonical model
//   (remaining / nextKind / break state / pause reasons) and `syncPhase()` projects it into an
//   `EnginePhase`. That keeps the many entry points (commands + signals) from drifting.
// * Two pause-reason sets are kept: `detectorReasons` (whatever TGDetection last published) and
//   `engineReasons` (`.idle`, `.screenLocked`, `.manual` — owned by the engine). The union is what
//   the UI sees, so a detector update can never clobber an engine-owned reason and vice versa.
//
// Implementation is split across:
//   BreakEngine.swift          — state, lifecycle, tick, phase projection
//   BreakEngine+Commands.swift — user commands (snooze/skip/start/end/pause…)
//   BreakEngine+Signals.swift  — detector signals (pause reasons, hints, idle, lock, wake, away)

import Foundation
import Combine

@MainActor
public final class BreakEngine: ObservableObject {

    // MARK: - Published state

    @Published public private(set) var phase: EnginePhase = .stopped
    /// Snoozes used today / this session (session = since last completed break).
    @Published public internal(set) var snoozesUsedToday: Int = 0
    @Published public internal(set) var snoozesUsedThisSession: Int = 0
    /// Ordinary skips used today (capped by `Settings.skipsPerDay` when it's non-zero).
    @Published public internal(set) var skipsUsedToday: Int = 0
    /// Advance skips used today (capped by `Settings.advanceSkipsPerDay`).
    @Published public internal(set) var advanceSkipsUsedToday: Int = 0
    /// Focus time accumulated in the current session (seconds of unpaused screen time).
    @Published public internal(set) var currentSessionFocusTime: TimeInterval = 0
    /// Short breaks completed since the last long break (drives "every Nth is long").
    @Published public internal(set) var shortBreaksSinceLong: Int = 0

    public let events = PassthroughSubject<EngineEvent, Never>()

    public var settings: Settings {
        didSet { settingsDidChange(from: oldValue) }
    }

    let clock: Clock

    // MARK: - Canonical model (internal so the extensions in sibling files can drive it)

    /// True between `start()` and `stop()`.
    var started = false
    /// Focus-seconds left before the next break fires. Clamped at 0 while a break is due/running.
    var remaining: TimeInterval = 0
    /// Kind of the break that `remaining` is counting down to.
    var nextKind: BreakKind = .short
    /// Wall-clock stamp of the last processed tick. `nil` until the engine starts.
    var lastTickAt: Date?
    /// Start-of-day for the day the engine last saw, used to detect calendar rollover.
    var currentDay: Date = .distantPast

    // Pre-break
    var inPreBreak = false
    var warningEmitted = false
    var lastCountdownSecond: Int?

    // Break in progress (nil ⇒ not in a break)
    var breakKind: BreakKind?
    var breakTotal: TimeInterval = 0
    var breakRemaining: TimeInterval = 0

    // Activity hints (typing/dragging/dictating) — these *delay*, they never freeze focus time.
    var activityHint: ActivityHint?
    var waitingForActivity = false
    var waitingHint: ActivityHint = .typing
    var hintClearedAt: Date?

    // Pause reasons
    var detectorReasons: Set<PauseReason> = []
    var engineReasons: Set<PauseReason> = []
    var lastEmittedReasons: Set<PauseReason> = []

    // Away tracking (idle + screen lock share one "away" episode)
    var awayBeganAt: Date?
    var awaySnapshot: AwaySnapshot?
    var awayBeganInBreak = false
    var lastAwayDecision: AwayDecision?

    /// How long the "Undo" affordance on an away decision stays live.
    public static let awayUndoWindow: TimeInterval = 30

    // MARK: - Init

    public init(settings: Settings, clock: Clock = SystemClock()) {
        self.settings = settings
        self.clock = clock
    }

    // MARK: - Lifecycle

    public func start() {
        let now = clock.now()
        started = true
        currentDay = Self.startOfDay(now)
        lastTickAt = now
        shortBreaksSinceLong = min(shortBreaksSinceLong, max(0, settings.longBreakEvery - 1))
        nextKind = computeNextKind()
        remaining = settings.shortBreakInterval
        currentSessionFocusTime = 0
        snoozesUsedThisSession = 0
        clearBreakState()
        clearPreBreakFlags()
        clearActivityWait()
        clearAwayTracking()
        engineReasons.remove(.outsideOfficeHours)
        syncOfficeHours(now: now)
        syncPhase()
    }

    public func stop() {
        started = false
        lastTickAt = nil
        engineReasons.remove(.outsideOfficeHours)
        clearBreakState()
        clearPreBreakFlags()
        clearActivityWait()
        clearAwayTracking()
        lastAwayDecision = nil
        syncPhase()
    }

    /// Advance the machine. Uses `clock.now()` so it's robust to sleep (wall-clock deltas, not tick counts).
    public func tick() {
        let now = clock.now()
        var dt = max(0, now.timeIntervalSince(lastTickAt ?? now))
        lastTickAt = now

        handleDayRollover(now: now)
        // An expiring manual pause can itself start a due break; that break must not then be
        // advanced by this tick's delta, so remember what we were doing beforehand.
        let wasInBreak = breakKind != nil
        expireManualPause(now: now)
        // A tick that crosses an office-hours boundary belongs to neither side cleanly, so its
        // delta is dropped rather than credited to the side that happens to be current after it.
        if syncOfficeHours(now: now) { dt = 0 }

        guard started, dt > 0 else { syncPhase(); return }

        if breakKind != nil {
            if wasInBreak { advanceBreak(dt: dt, now: now) }
        } else if isPausedNow {
            // Focus time is frozen while paused; nothing accrues, nothing fires.
        } else {
            advanceCounting(dt: dt, now: now)
        }
        syncPhase()
    }

    // MARK: - Advancing

    func advanceBreak(dt: TimeInterval, now: Date) {
        guard let kind = breakKind else { return }
        breakRemaining -= dt
        if breakRemaining <= 0 {
            breakRemaining = 0
            emit(.breakTick(kind: kind, remaining: 0))
            completeBreak(now: now)
        } else {
            emit(.breakTick(kind: kind, remaining: breakRemaining))
        }
    }

    func advanceCounting(dt: TimeInterval, now: Date) {
        // Focus time accrues in .running / .preBreak / .waitingForActivityToStop.
        currentSessionFocusTime += dt

        if waitingForActivity {
            if activityHint != nil {
                hintClearedAt = nil
            } else {
                if hintClearedAt == nil { hintClearedAt = now }
                if let cleared = hintClearedAt,
                   now.timeIntervalSince(cleared) >= settings.typingBufferSeconds {
                    beginBreak(kind: nextKind, duration: duration(for: nextKind), now: now)
                }
            }
            return
        }

        remaining -= dt
        if remaining <= 0 {
            remaining = 0
            // A large wall-clock jump that lands past zero goes straight to the break: no phantom
            // pre-break warning and no burst of countdown pills for seconds that already elapsed.
            beginDueBreak(now: now)
            return
        }
        emitPreBreakSignals()
    }

    /// Emits `.preBreakWarning` once, then at most one `.preBreakCountdown` per integer second.
    func emitPreBreakSignals() {
        guard remaining > 0, remaining <= settings.preBreakWarningSeconds else { return }
        if !warningEmitted {
            warningEmitted = true
            inPreBreak = true
            emit(.preBreakWarning(kind: nextKind, startsIn: remaining))
        }
        inPreBreak = true

        let secondsLeft = Int(ceil(remaining))
        guard secondsLeft >= 1, secondsLeft <= settings.cursorCountdownSeconds else { return }
        guard secondsLeft != lastCountdownSecond else { return }
        lastCountdownSecond = secondsLeft
        emit(.preBreakCountdown(kind: nextKind, secondsLeft: secondsLeft))
    }

    // MARK: - Break start / finish

    /// The break is due right now. Defer for an activity hint if configured, otherwise start it.
    ///
    /// Dictation is the exception to `deferWhileTyping`: it rides the microphone, not the keyboard,
    /// and dropping an overlay mid-sentence loses the sentence. Turning off typing deferral is a
    /// statement about typing, so `.dictating` always defers.
    func beginDueBreak(now: Date) {
        if let hint = activityHint, settings.deferWhileTyping || hint == .dictating {
            waitingForActivity = true
            waitingHint = hint
            hintClearedAt = nil
            inPreBreak = false
            return
        }
        beginBreak(kind: nextKind, duration: duration(for: nextKind), now: now)
    }

    func beginBreak(kind: BreakKind, duration total: TimeInterval, now: Date) {
        breakKind = kind
        breakTotal = max(0, total)
        breakRemaining = max(0, total)
        remaining = 0
        clearPreBreakFlags()
        clearActivityWait()
        emit(.breakStarted(kind: kind, duration: breakTotal))
    }

    /// The break ran to completion (or was ended early past the allowed fraction).
    func completeBreak(now: Date) {
        guard let kind = breakKind else { return }
        emit(.breakEnded(kind: kind, completed: true))
        if kind == .long {
            shortBreaksSinceLong = 0
        } else {
            shortBreaksSinceLong += 1
        }
        clearBreakState()
        // A completed break ends the session: session snoozes and focus time reset.
        snoozesUsedThisSession = 0
        currentSessionFocusTime = 0
        restartInterval(recomputeKind: true)
    }

    /// Put a fresh focus interval on the clock. `recomputeKind: false` keeps the same next break kind
    /// (used by skip, so skipping a long break means the next one is still long).
    func restartInterval(recomputeKind: Bool) {
        remaining = settings.shortBreakInterval
        if recomputeKind { nextKind = computeNextKind() }
        clearPreBreakFlags()
        clearActivityWait()
    }

    func computeNextKind() -> BreakKind {
        guard settings.longBreaksEnabled, settings.longBreakEvery > 0 else { return .short }
        return shortBreaksSinceLong + 1 >= settings.longBreakEvery ? .long : .short
    }

    func duration(for kind: BreakKind) -> TimeInterval {
        kind == .long ? settings.longBreakDuration : settings.shortBreakDuration
    }

    // MARK: - Day rollover

    static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    func handleDayRollover(now: Date) {
        let today = Self.startOfDay(now)
        guard currentDay != .distantPast, today != currentDay else {
            if currentDay == .distantPast { currentDay = today }
            return
        }
        currentDay = today
        snoozesUsedToday = 0
        skipsUsedToday = 0
        advanceSkipsUsedToday = 0
        shortBreaksSinceLong = 0
        if breakKind == nil { nextKind = computeNextKind() }
    }

    // MARK: - Settings

    func settingsDidChange(from old: Settings) {
        guard old != settings else { return }

        // Changing the interval mid-run shifts the deadline by the delta — it never restarts it.
        let delta = settings.shortBreakInterval - old.shortBreakInterval
        if delta != 0, started, breakKind == nil, !waitingForActivity {
            remaining = max(0, remaining + delta)
            if remaining > settings.preBreakWarningSeconds { clearPreBreakFlags() }
        }
        if old.longBreaksEnabled != settings.longBreaksEnabled || old.longBreakEvery != settings.longBreakEvery {
            if breakKind == nil { nextKind = computeNextKind() }
        }
        if old.officeHoursEnabled != settings.officeHoursEnabled
            || old.officeHoursStart != settings.officeHoursStart
            || old.officeHoursEnd != settings.officeHoursEnd
            || old.officeDays != settings.officeDays {
            syncOfficeHours(now: clock.now())
        }
        syncPhase()
    }

    // MARK: - Phase projection

    var allPauseReasons: Set<PauseReason> { detectorReasons.union(engineReasons) }
    var isPausedNow: Bool { !allPauseReasons.isEmpty }

    func syncPhase() {
        let next: EnginePhase
        if !started {
            next = .stopped
        } else if let kind = breakKind {
            next = .inBreak(kind: kind, remaining: breakRemaining, total: breakTotal)
        } else {
            let reasons = allPauseReasons
            if !reasons.isEmpty {
                next = .paused(reasons: reasons, nextBreak: nextKind, remaining: remaining)
            } else if waitingForActivity {
                next = .waitingForActivityToStop(kind: nextKind, hint: activityHint ?? waitingHint)
            } else if inPreBreak {
                next = .preBreak(kind: nextKind, remaining: remaining)
            } else {
                next = .running(nextBreak: nextKind, remaining: remaining)
            }
        }
        if next != phase { phase = next }
    }

    // MARK: - Small helpers

    func emit(_ event: EngineEvent) { events.send(event) }

    func clearPreBreakFlags() {
        inPreBreak = false
        warningEmitted = false
        lastCountdownSecond = nil
    }

    func clearActivityWait() {
        waitingForActivity = false
        hintClearedAt = nil
    }

    func clearBreakState() {
        breakKind = nil
        breakTotal = 0
        breakRemaining = 0
    }

    func clearAwayTracking() {
        awayBeganAt = nil
        awaySnapshot = nil
        awayBeganInBreak = false
    }

    // MARK: - Derived / read-only surface for UI

    public var canSkipNow: Bool {
        guard hasSkipBudgetToday else { return false }
        switch settings.enforcement {
        case .hardcore:
            return false
        case .casual:
            switch phase {
            case .preBreak, .inBreak: return true
            default: return false
            }
        case .balanced:
            switch phase {
            case .preBreak: return true
            case .inBreak: return breakElapsed >= settings.balancedSkipDelaySeconds
            default: return false
            }
        }
    }

    public var canEndBreakEarly: Bool {
        guard breakKind != nil, breakTotal > 0 else { return false }
        return breakElapsed / breakTotal >= settings.allowEndBreakEarlyAfterFraction
    }

    public var snoozesRemainingToday: Int { max(0, settings.snoozesPerDay - snoozesUsedToday) }
    public var snoozesRemainingThisSession: Int { max(0, settings.snoozesPerSession - snoozesUsedThisSession) }
    public var canSnoozeNow: Bool { isSnoozablePhase && snoozesRemainingToday > 0 && snoozesRemainingThisSession > 0 }

    /// Focus-seconds left before the next break (0 while a break is due or running).
    public var remainingUntilBreak: TimeInterval { remaining }
    /// The kind of break `remainingUntilBreak` is counting down to.
    public var nextBreakKind: BreakKind { nextKind }
    /// Seconds elapsed in the current break (0 when not in one).
    public var breakElapsed: TimeInterval { breakKind == nil ? 0 : max(0, breakTotal - breakRemaining) }
    /// True while an away decision can still be undone.
    public var canUndoAwayDecision: Bool {
        guard let decision = lastAwayDecision else { return false }
        return clock.now().timeIntervalSince(decision.at) <= Self.awayUndoWindow
    }

    var isSnoozablePhase: Bool {
        switch phase {
        case .preBreak, .waitingForActivityToStop, .inBreak: return true
        default: return false
        }
    }
}

// MARK: - Away bookkeeping types

/// Everything needed to put the engine back the way it was before an away episode.
struct AwaySnapshot {
    var remaining: TimeInterval
    var nextKind: BreakKind
    var inPreBreak: Bool
    var warningEmitted: Bool
    var lastCountdownSecond: Int?
    var shortBreaksSinceLong: Int
    var snoozesUsedThisSession: Int
    var focusTime: TimeInterval
}

/// The decision the engine made when the user came back, kept so `undoAwayDecision()` can flip it.
struct AwayDecision {
    var at: Date
    var resetTimer: Bool
    var awayFor: TimeInterval
    var snapshot: AwaySnapshot
}
