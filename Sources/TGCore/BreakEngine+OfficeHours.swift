// TGCore — BreakEngine: office hours.
//
// Outside the configured window the engine behaves exactly as if it were paused: focus time
// freezes, no break fires, and the UI shows the ordinary paused presentation with "Off hours".
// The reason is engine-owned (like `.idle` and `.screenLocked`), so a detector update can't drop it.
//
// Crossing *into* office hours starts a fresh interval: a new working day shouldn't inherit
// yesterday's half-elapsed timer when the user shut the lid before `idleResetAfter` could fire.

import Foundation

extension PauseReason {
    var isOutsideOfficeHours: Bool {
        if case .outsideOfficeHours = self { return true }
        return false
    }
}

extension BreakEngine {

    /// True when office hours are off, or when the clock is currently inside the window.
    public var isWithinOfficeHours: Bool {
        OfficeHours.contains(clock.now(), settings: settings)
    }

    /// Whether the engine is sitting out the clock because of office hours.
    public var isOutsideOfficeHours: Bool {
        engineReasons.contains(where: { $0.isOutsideOfficeHours })
    }

    /// Adds or drops the `.outsideOfficeHours` reason. Returns true when the side of the window
    /// changed on this call — `tick()` then drops the elapsed delta rather than crediting it to
    /// whichever side happened to be current afterwards.
    @discardableResult
    func syncOfficeHours(now: Date) -> Bool {
        guard started else { return false }
        let inside = OfficeHours.contains(now, settings: settings)
        let paused = isOutsideOfficeHours
        guard inside == paused else { return false }

        if inside {
            engineReasons.remove(.outsideOfficeHours)
            beginFreshOfficeDay()
            syncPauseState(now: now)
        } else {
            engineReasons.insert(.outsideOfficeHours)
            syncPauseState(now: now)
        }
        return true
    }

    /// A working day starts on a whole interval with a clean session. Deliberately keeps the
    /// long-break cadence — an evening away doesn't earn a long break, and doesn't lose one either.
    func beginFreshOfficeDay() {
        snoozesUsedThisSession = 0
        currentSessionFocusTime = 0
        clearAwayTracking()
        restartInterval(recomputeKind: false)
    }
}
