// TGCore — BreakEngine: inbound signals from TGDetection and from the system (idle, lock, wake).
//
// Two reason sets are kept apart on purpose:
//   * `detectorReasons` — replaced wholesale every time ActivityMonitor publishes.
//   * `engineReasons`   — `.idle`, `.screenLocked`, `.manual`; owned here so a detector update can
//                         never drop them (and vice versa).
// The union is what the UI sees and what freezes focus time.

import Foundation

// MARK: - PauseReason helpers (internal — Contracts.swift stays untouched)

extension PauseReason {
    /// Meeting / video end abruptly; give the user `cooldownAfterActivity` before a break can fire.
    var needsCooldown: Bool {
        switch self {
        case .meeting, .video: return true
        default: return false
        }
    }

    var isManual: Bool {
        if case .manual = self { return true }
        return false
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var isScreenLocked: Bool {
        if case .screenLocked = self { return true }
        return false
    }
}

extension BreakEngine {

    // MARK: - Detector-published pause reasons

    public func updatePauseReasons(_ reasons: Set<PauseReason>) {
        // Engine-owned reasons are never taken from the detector set.
        let sanitised = reasons.filter { !$0.isIdle && !$0.isScreenLocked && !$0.isManual }
        guard sanitised != detectorReasons else { return }
        // Bring the wall-clock model up to date *before* the pause set changes, so the seconds
        // since the last tick land on the right side of the freeze.
        tick()
        detectorReasons = sanitised
        let now = clock.now()
        syncPauseState(now: now)
        evaluateDueBreak(now: now)
        syncPhase()
    }

    /// Emits `.paused` / `.resumed` when the union changes, and applies the post-activity cooldown.
    func syncPauseState(now: Date) {
        let combined = allPauseReasons
        guard combined != lastEmittedReasons else { return }
        let previous = lastEmittedReasons
        lastEmittedReasons = combined

        guard started else { return }

        if combined.isEmpty {
            // A break must not fire the instant a call or video ends.
            if previous.contains(where: { $0.needsCooldown }), breakKind == nil,
               remaining < settings.cooldownAfterActivity {
                remaining = settings.cooldownAfterActivity
                if remaining > settings.preBreakWarningSeconds { clearPreBreakFlags() }
            }
            emit(.resumed)
        } else {
            emit(.paused(reasons: combined))
        }
    }

    /// A break that came due while paused (or that the cooldown didn't push back) fires on resume.
    func evaluateDueBreak(now: Date) {
        guard started, breakKind == nil, !isPausedNow, !waitingForActivity, remaining <= 0 else { return }
        remaining = 0
        beginDueBreak(now: now)
    }

    // MARK: - Activity hints

    public func updateActivityHint(_ hint: ActivityHint?) {
        guard hint != activityHint else { return }
        activityHint = hint
        if waitingForActivity {
            if let hint {
                waitingHint = hint
                hintClearedAt = nil
            } else {
                hintClearedAt = clock.now()
            }
        }
        syncPhase()
    }

    // MARK: - Idle

    public func updateIdleSeconds(_ seconds: TimeInterval) {
        guard started else { return }
        tick()
        let now = clock.now()
        let isIdle = engineReasons.contains(where: { $0.isIdle })

        if seconds >= settings.idlePauseAfter {
            guard !isIdle else { return }
            engineReasons.insert(.idle)
            // The user actually went away when input stopped, not when we noticed.
            noteAwayBegan(at: now.addingTimeInterval(-seconds))
            syncPauseState(now: now)
            syncPhase()
        } else {
            guard isIdle else { return }
            engineReasons.remove(.idle)
            syncPauseState(now: now)
            finishAwayIfEnded(now: now)
            evaluateDueBreak(now: now)
            syncPhase()
        }
    }

    // MARK: - Screen lock

    public func screenDidLock() {
        guard started else { return }
        guard !engineReasons.contains(where: { $0.isScreenLocked }) else { return }
        tick()
        let now = clock.now()
        engineReasons.insert(.screenLocked)
        noteAwayBegan(at: now)
        syncPauseState(now: now)
        syncPhase()
    }

    public func screenDidUnlock() {
        guard engineReasons.contains(where: { $0.isScreenLocked }) else { return }
        tick()
        let now = clock.now()
        engineReasons.remove(.screenLocked)
        syncPauseState(now: now)
        finishAwayIfEnded(now: now)
        evaluateDueBreak(now: now)
        syncPhase()
    }

    // MARK: - Wake

    /// Called on `NSWorkspace.didWakeNotification`. Wall-clock deltas already do the right thing for
    /// small jumps, so this mostly exists to classify a *long* sleep as time spent away from the
    /// screen rather than as focus time that should immediately trigger a break.
    public func systemDidWake() {
        guard started else { return }
        let now = clock.now()
        let jump = max(0, now.timeIntervalSince(lastTickAt ?? now))

        let sleptThroughABreak = jump >= settings.idleResetAfter
        guard sleptThroughABreak, breakKind == nil, !isPausedNow else {
            tick()
            return
        }

        lastTickAt = now
        handleDayRollover(now: now)
        noteAwayBegan(at: now.addingTimeInterval(-jump))
        applyAwayDecision(awayFor: jump, now: now)
        syncPhase()
    }

    // MARK: - Away episodes (idle + lock + sleep share one episode)

    func noteAwayBegan(at date: Date) {
        guard awayBeganAt == nil else {
            // Overlapping sources (idle then lock): keep the earliest start.
            if let existing = awayBeganAt, date < existing { awayBeganAt = date }
            return
        }
        awayBeganAt = date
        awayBeganInBreak = breakKind != nil
        awaySnapshot = AwaySnapshot(
            remaining: remaining,
            nextKind: nextKind,
            inPreBreak: inPreBreak,
            warningEmitted: warningEmitted,
            lastCountdownSecond: lastCountdownSecond,
            shortBreaksSinceLong: shortBreaksSinceLong,
            snoozesUsedThisSession: snoozesUsedThisSession,
            focusTime: currentSessionFocusTime
        )
    }

    /// Runs once every away source (idle, lock) has cleared.
    func finishAwayIfEnded(now: Date) {
        guard !engineReasons.contains(where: { $0.isIdle || $0.isScreenLocked }) else { return }
        guard let began = awayBeganAt else { return }
        let awayFor = max(0, now.timeIntervalSince(began))
        applyAwayDecision(awayFor: awayFor, now: now)
    }

    /// Long enough away ⇒ treat it as a break already taken and put a fresh interval up.
    /// Short away ⇒ just carry on. Either way the decision is silent apart from `.awayDecision`,
    /// which the UI shows as a toast with an Undo button.
    func applyAwayDecision(awayFor: TimeInterval, now: Date) {
        let snapshot = awaySnapshot ?? AwaySnapshot(
            remaining: remaining, nextKind: nextKind, inPreBreak: inPreBreak,
            warningEmitted: warningEmitted, lastCountdownSecond: lastCountdownSecond,
            shortBreaksSinceLong: shortBreaksSinceLong,
            snoozesUsedThisSession: snoozesUsedThisSession, focusTime: currentSessionFocusTime
        )
        let startedInBreak = awayBeganInBreak
        clearAwayTracking()

        // A break that was already on screen when the user locked/idled keeps running; it isn't
        // "time away from the machine" in any sense we should act on.
        guard !startedInBreak, breakKind == nil else { return }

        if awayFor >= settings.idleResetAfter {
            resetIntervalAsBreakTaken()
            lastAwayDecision = AwayDecision(at: now, resetTimer: true, awayFor: awayFor, snapshot: snapshot)
            emit(.awayDecision(resetTimer: true, awayFor: awayFor))
        } else {
            lastAwayDecision = AwayDecision(at: now, resetTimer: false, awayFor: awayFor, snapshot: snapshot)
            // Blips (a quick lock/unlock) stay completely silent — no toast, no undo prompt.
            if awayFor >= settings.idlePauseAfter {
                emit(.awayDecision(resetTimer: false, awayFor: awayFor))
            }
        }
    }

    /// The user was away long enough that it counted as a break: fresh interval, fresh session.
    /// Deliberately does *not* advance the long-break cadence — an unattended machine shouldn't be
    /// able to earn its way to a long break.
    func resetIntervalAsBreakTaken() {
        snoozesUsedThisSession = 0
        currentSessionFocusTime = 0
        restartInterval(recomputeKind: false)
    }

    /// Undo the last automatic away decision (toast "Undo"), within `awayUndoWindow`.
    public func undoAwayDecision() {
        guard let decision = lastAwayDecision else { return }
        let now = clock.now()
        guard now.timeIntervalSince(decision.at) <= Self.awayUndoWindow else { return }
        guard breakKind == nil else { return }
        lastAwayDecision = nil

        if decision.resetTimer {
            // "No, I was here" — put the pre-away timer back.
            let snapshot = decision.snapshot
            remaining = snapshot.remaining
            nextKind = snapshot.nextKind
            inPreBreak = snapshot.inPreBreak
            warningEmitted = snapshot.warningEmitted
            lastCountdownSecond = snapshot.lastCountdownSecond
            shortBreaksSinceLong = snapshot.shortBreaksSinceLong
            snoozesUsedThisSession = snapshot.snoozesUsedThisSession
            currentSessionFocusTime = snapshot.focusTime
            emit(.awayDecision(resetTimer: false, awayFor: decision.awayFor))
        } else {
            // "That was a break" — reset after all.
            resetIntervalAsBreakTaken()
            emit(.awayDecision(resetTimer: true, awayFor: decision.awayFor))
        }
        evaluateDueBreak(now: now)
        syncPhase()
    }
}
