// TGCore — BreakEngine: commands issued by the user (menu bar, overlay buttons, hotkeys).
// Every command is a no-op when it isn't legal in the current phase; nothing here throws or traps.

import Foundation

extension BreakEngine {

    // MARK: - Starting a break on demand

    /// "Start break now" from the quick panel / hotkey. Legal from any non-stopped phase, including
    /// while paused (an explicit user request outranks Smart Pause).
    public func startBreakNow(_ kind: BreakKind) {
        guard started, breakKind == nil else { return }
        nextKind = kind
        beginBreak(kind: kind, duration: duration(for: kind), now: clock.now())
        syncPhase()
    }

    /// A one-off break of an arbitrary length. Counts as a short break for the long-break cadence.
    public func startCustomBreak(duration customDuration: TimeInterval) {
        guard started, breakKind == nil, customDuration > 0 else { return }
        nextKind = .short
        beginBreak(kind: .short, duration: customDuration, now: clock.now())
        syncPhase()
    }

    // MARK: - Snooze

    /// Push the break back by `seconds`. Only legal from `.preBreak`, `.waitingForActivityToStop`
    /// and `.inBreak`, and only while both the daily and the session budget have room.
    public func snooze(_ seconds: TimeInterval) {
        guard started, seconds > 0, isSnoozablePhase else { return }
        guard snoozesRemainingToday > 0, snoozesRemainingThisSession > 0 else { return }

        let kind = breakKind ?? nextKind
        if breakKind != nil {
            emit(.breakEnded(kind: kind, completed: false))
            clearBreakState()
        }

        snoozesUsedToday += 1
        snoozesUsedThisSession += 1

        remaining = max(0, remaining) + seconds
        nextKind = kind
        clearPreBreakFlags()
        clearActivityWait()
        emit(.snoozed(kind: kind, by: seconds))
        syncPhase()
    }

    // MARK: - Skip

    /// Drop this break entirely. Gated by `canSkipNow` (enforcement level, how long the break has
    /// run, and the daily skip budget when `Settings.skipsPerDay` sets one).
    /// A skipped long break still satisfies the long-break cadence, so the next break is a short
    /// one — skipping a long break must not leave another long break owed right behind it.
    public func skipBreak() {
        guard started, canSkipNow else { return }
        skipsUsedToday += 1
        let kind = breakKind ?? nextKind
        if breakKind != nil {
            emit(.breakEnded(kind: kind, completed: false))
            clearBreakState()
        }
        if kind == .long { shortBreaksSinceLong = 0 }
        emit(.skipped(kind: kind))
        restartInterval(recomputeKind: true)
        syncPhase()
    }

    // MARK: - End early

    /// "End break" — only offered once enough of the break has elapsed. Counts as completed, so it
    /// advances the cadence and clears the session snooze budget.
    public func endBreakEarly() {
        guard started, canEndBreakEarly else { return }
        completeBreak(now: clock.now())
        syncPhase()
    }

    // MARK: - Add time

    /// "+1 minute" from the pre-break card. If the extra minute lifts the deadline back above the
    /// warning threshold the card goes away and the engine returns to plain `.running`.
    public func addMinute() {
        addTime(60)
    }

    /// Generic "+N seconds" (the pre-break card offers +1m / +5m / +15m).
    public func addTime(_ seconds: TimeInterval) {
        guard started, seconds > 0, breakKind == nil else { return }
        switch phase {
        case .running, .preBreak:
            remaining += seconds
            if remaining > settings.preBreakWarningSeconds {
                clearPreBreakFlags()
            } else {
                lastCountdownSecond = nil
            }
            syncPhase()
        default:
            return
        }
    }

    // MARK: - Manual pause

    /// Pause by hand. `duration == nil` pauses indefinitely; otherwise it auto-expires on a later tick.
    public func pauseManually(for duration: TimeInterval?) {
        guard started else { return }
        tick()
        let now = clock.now()
        removeManualPauseReasons()
        engineReasons.insert(.manual(until: duration.map { now.addingTimeInterval($0) }))
        syncPauseState(now: now)
        syncPhase()
    }

    public func resumeManually() {
        guard engineReasons.contains(where: { $0.isManual }) else { return }
        tick()
        removeManualPauseReasons()
        let now = clock.now()
        syncPauseState(now: now)
        evaluateDueBreak(now: now)
        syncPhase()
    }

    @discardableResult
    func removeManualPauseReasons() -> Bool {
        let manual = engineReasons.filter { $0.isManual }
        guard !manual.isEmpty else { return false }
        engineReasons.subtract(manual)
        return true
    }

    /// Drops `.manual(until:)` reasons whose deadline has passed. Called from every tick.
    func expireManualPause(now: Date) {
        let expired = engineReasons.filter {
            if case .manual(let until) = $0, let until, until <= now { return true }
            return false
        }
        guard !expired.isEmpty else { return }
        engineReasons.subtract(expired)
        syncPauseState(now: now)
        evaluateDueBreak(now: now)
    }
}
