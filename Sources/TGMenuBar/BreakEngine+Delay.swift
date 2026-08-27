// TGMenuBar — "can I push this break back right now?", derived rather than added to TGCore.
import Foundation
import TGCore

extension BreakEngine {

    /// Whether the "+1m / +5m / +15m" controls would actually change anything.
    ///
    /// Two different engine commands sit behind one button. While the interval is still
    /// counting, `addTime` simply moves the deadline. Once the break is imminent — or already
    /// on screen — the only way back is `snooze`, which spends the daily/session budget and
    /// is a no-op when that budget is gone. Neither command applies while paused or stopped.
    var canDelayNow: Bool {
        switch phase {
        case .running, .preBreak:
            return true
        case .waitingForActivityToStop, .inBreak:
            return canSnoozeNow
        case .stopped, .paused:
            return false
        }
    }

    /// True while both snooze budgets still have room. Nothing consults it today — the panel's
    /// "+5 min" follows `canDelayNow`, which already folds the budget in for the phases where
    /// spending it is the only way to delay — but the rule is worth stating in one place.
    var hasSnoozeBudget: Bool {
        snoozesRemainingToday > 0 && snoozesRemainingThisSession > 0
    }
}
