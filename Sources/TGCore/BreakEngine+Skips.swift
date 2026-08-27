// TGCore — BreakEngine: advance skips and the per-day skip budget.
//
// Two separate budgets, on purpose:
//   * `skipsPerDay` caps ordinary skips — dismissing a break that is already on screen or imminent.
//   * `advanceSkipsPerDay` caps *advance* skips — throwing away the upcoming break while the
//     interval is still counting, so it never interrupts at all.
// Spending one never spends the other; each is its own decision with its own daily allowance.
//
// Hardcore never skips, by either route.

import Foundation

extension BreakEngine {

    // MARK: - Budgets

    /// Advance skips left today. Meaningless while `advanceSkipsEnabled` is false.
    public var advanceSkipsRemainingToday: Int {
        max(0, settings.advanceSkipsPerDay - advanceSkipsUsedToday)
    }

    /// Ordinary skips left today, or `nil` when they're unlimited (`skipsPerDay == 0`).
    public var skipsRemainingToday: Int? {
        guard settings.skipsPerDay > 0 else { return nil }
        return max(0, settings.skipsPerDay - skipsUsedToday)
    }

    /// False only when a daily cap is set and spent.
    var hasSkipBudgetToday: Bool {
        guard let left = skipsRemainingToday else { return true }
        return left > 0
    }

    // MARK: - Advance skip

    /// Whether "Skip next break" would do anything right now: enabled, allowance left, not
    /// hardcore, and the interval still plainly counting (not pre-break, paused, or in a break).
    public var canAdvanceSkip: Bool {
        guard started, settings.advanceSkipsEnabled, settings.enforcement != .hardcore else { return false }
        guard advanceSkipsRemainingToday > 0 else { return false }
        if case .running = phase { return true }
        return false
    }

    /// Throw away the upcoming break before it ever shows: the interval restarts immediately,
    /// exactly as if the break had appeared and been skipped. Like `skipBreak()` it does not
    /// advance the long-break cadence — a skipped long break is still owed.
    public func skipNextBreak() {
        guard canAdvanceSkip else { return }
        advanceSkipsUsedToday += 1
        let kind = nextKind
        emit(.skipped(kind: kind))
        restartInterval(recomputeKind: false)
        syncPhase()
    }
}
