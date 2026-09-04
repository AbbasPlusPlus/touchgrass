// Advance skips (throwing away the next break before it appears) and the per-day skip budget.

import Foundation
import Testing
@testable import TGCore

// MARK: - Fixtures

/// Fast settings with advance skips switched on and skipping unlocked (casual).
private func advanceSettings(perDay: Int = 2) -> Settings {
    var s = Settings.fast()
    s.enforcement = .casual
    s.advanceSkipsEnabled = true
    s.advanceSkipsPerDay = perDay
    return s
}

// MARK: - Advance skips

@Test @MainActor func advanceSkipIsUnavailableUntilItIsSwitchedOn() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(10)
    #expect(!h.engine.canAdvanceSkip)
    h.engine.skipNextBreak()
    #expect(h.events.skips.isEmpty)
    #expect(h.engine.remainingUntilBreak == 90)
}

@Test @MainActor func advanceSkipRestartsTheIntervalAndReportsASkip() {
    let h = Harness(advanceSettings())
    h.engine.start()
    h.run(40)
    #expect(h.engine.canAdvanceSkip)
    h.clearEvents()
    h.engine.skipNextBreak()
    #expect(h.events.skips == [.short])
    #expect(h.engine.remainingUntilBreak == 100)
    #expect(h.engine.advanceSkipsUsedToday == 1)
    #expect(h.engine.phase == .running(nextBreak: .short, remaining: 100))
}

@Test @MainActor func advanceSkipsRunOutForTheDay() {
    let h = Harness(advanceSettings(perDay: 2))
    h.engine.start()
    h.run(10)
    h.engine.skipNextBreak()
    h.run(10)
    h.engine.skipNextBreak()
    #expect(h.engine.advanceSkipsUsedToday == 2)
    #expect(h.engine.advanceSkipsRemainingToday == 0)
    #expect(!h.engine.canAdvanceSkip)

    h.clearEvents()
    h.engine.skipNextBreak()
    #expect(h.events.skips.isEmpty)
    #expect(h.engine.advanceSkipsUsedToday == 2)
}

@Test @MainActor func advanceSkipIsOnlyOfferedWhileTheIntervalIsPlainlyCounting() {
    let h = Harness(advanceSettings())
    h.engine.start()
    h.run(95)                                     // pre-break: too late to skip in advance
    #expect(h.engine.phase.isPreBreak)
    #expect(!h.engine.canAdvanceSkip)

    h.run(10)                                     // now in the break itself
    #expect(h.engine.phase.isInBreak)
    #expect(!h.engine.canAdvanceSkip)
}

@Test @MainActor func advanceSkipIsUnavailableWhilePausedOrStopped() {
    let h = Harness(advanceSettings())
    #expect(!h.engine.canAdvanceSkip)             // stopped
    h.engine.start()
    h.run(10)
    h.engine.updatePauseReasons([.zoomMeeting])
    #expect(!h.engine.canAdvanceSkip)
    h.engine.skipNextBreak()
    #expect(h.events.skips.isEmpty)
}

@Test @MainActor func hardcoreNeverSkips() {
    var s = advanceSettings()
    s.enforcement = .hardcore
    let h = Harness(s)
    h.engine.start()
    h.run(10)
    #expect(!h.engine.canAdvanceSkip)
    h.engine.skipNextBreak()
    #expect(h.events.skips.isEmpty)
    #expect(h.engine.remainingUntilBreak == 90)

    h.run(90)                                     // and the break still happens
    #expect(h.engine.phase.isInBreak)
    #expect(!h.engine.canSkipNow)
}

@Test @MainActor func advanceSkipWorksInBalancedToo() {
    var s = advanceSettings()
    s.enforcement = .balanced
    let h = Harness(s)
    h.engine.start()
    h.run(10)
    #expect(h.engine.canAdvanceSkip)
    h.engine.skipNextBreak()
    #expect(h.engine.remainingUntilBreak == 100)
}

@Test @MainActor func advanceSkippingALongBreakMakesTheNextBreakShort() {
    var s = advanceSettings()
    s.longBreakEvery = 2
    let h = Harness(s)
    h.engine.start()
    h.run(110)                                    // one short break completed
    #expect(h.engine.nextBreakKind == .long)
    h.run(10)
    h.engine.skipNextBreak()
    // Skipping the long break satisfies the cadence: the next break is short, not another long.
    #expect(h.engine.nextBreakKind == .short)
    #expect(h.engine.shortBreaksSinceLong == 0)
}

// MARK: - Ordinary skip budget

@Test @MainActor func skipsAreUnlimitedWhenThePerDayCapIsZero() {
    var s = Settings.fast()
    s.enforcement = .casual
    s.skipsPerDay = 0
    let h = Harness(s)
    h.engine.start()
    for _ in 0..<5 {
        h.run(95)
        #expect(h.engine.canSkipNow)
        h.engine.skipBreak()
    }
    #expect(h.engine.skipsUsedToday == 5)
    #expect(h.engine.skipsRemainingToday == nil)
}

@Test @MainActor func aPerDaySkipCapClosesSkippingForTheRestOfTheDay() {
    var s = Settings.fast()
    s.enforcement = .casual
    s.skipsPerDay = 2
    let h = Harness(s)
    h.engine.start()

    h.run(95)
    h.engine.skipBreak()
    h.run(95)
    h.engine.skipBreak()
    #expect(h.engine.skipsUsedToday == 2)
    #expect(h.engine.skipsRemainingToday == 0)

    h.run(95)
    #expect(!h.engine.canSkipNow)
    h.clearEvents()
    h.engine.skipBreak()
    #expect(h.events.skips.isEmpty)
    #expect(h.engine.skipsUsedToday == 2)

    h.run(10)                                     // the break happens instead
    #expect(h.engine.phase.isInBreak)
}

@Test @MainActor func theTwoBudgetsAreSpentSeparately() {
    var s = advanceSettings(perDay: 2)
    s.skipsPerDay = 2
    let h = Harness(s)
    h.engine.start()

    h.run(10)
    h.engine.skipNextBreak()
    #expect(h.engine.skipsUsedToday == 0)         // an advance skip is not an ordinary skip
    #expect(h.engine.skipsRemainingToday == 2)

    h.run(95)
    h.engine.skipBreak()
    #expect(h.engine.advanceSkipsUsedToday == 1)  // …and vice versa
    #expect(h.engine.skipsUsedToday == 1)
}

@Test @MainActor func bothBudgetsRefillAtMidnight() {
    var s = advanceSettings(perDay: 1)
    s.skipsPerDay = 1
    let h = Harness(s)
    h.engine.start()
    h.run(10)
    h.engine.skipNextBreak()
    h.run(95)
    h.engine.skipBreak()
    #expect(h.engine.advanceSkipsUsedToday == 1)
    #expect(h.engine.skipsUsedToday == 1)
    #expect(!h.engine.canAdvanceSkip)

    h.engine.updatePauseReasons([.xcodeFullscreen])   // freeze so the jump doesn't fire a break
    h.jump(24 * 3600)
    h.engine.updatePauseReasons([])
    #expect(h.engine.advanceSkipsUsedToday == 0)
    #expect(h.engine.skipsUsedToday == 0)
    #expect(h.engine.skipsRemainingToday == 1)
    #expect(h.engine.canAdvanceSkip)
}
