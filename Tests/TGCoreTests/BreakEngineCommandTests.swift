// Snooze budgets, skip rules per enforcement level, end-early, add-time, on-demand breaks,
// and the typing/dragging deferral.

import Foundation
import Testing
@testable import TGCore

// MARK: - Snooze

@Test @MainActor func snoozeFromPreBreakAddsTimeAndReturnsToRunning() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(95)                                     // remaining 5, pre-break
    h.clearEvents()
    h.engine.snooze(30)
    #expect(h.events.snoozes.count == 1)
    #expect(h.events.snoozes.first?.1 == 30)
    #expect(h.engine.phase == .running(nextBreak: .short, remaining: 35))
    #expect(h.engine.snoozesUsedToday == 1)
    #expect(h.engine.snoozesUsedThisSession == 1)
}

@Test @MainActor func snoozeDuringABreakEndsItUncompletedFirst() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(103)                                    // 3s into the break
    h.clearEvents()
    h.engine.snooze(60)
    #expect(h.events.breakEndings.first?.1 == false)
    #expect(h.events.snoozes.count == 1)
    #expect(h.engine.phase == .running(nextBreak: .short, remaining: 60))
    #expect(h.engine.shortBreaksSinceLong == 0)   // an interrupted break does not count
}

@Test @MainActor func snoozeFromWaitingForActivityIsAllowed() {
    var s = Settings.fast()
    s.deferWhileTyping = true
    let h = Harness(s)
    h.engine.start()
    h.engine.updateActivityHint(.typing)
    h.run(100)
    #expect(h.engine.phase.isWaitingForActivity)
    h.engine.snooze(45)
    #expect(h.engine.phase == .running(nextBreak: .short, remaining: 45))
}

@Test @MainActor func snoozeIsIgnoredWhileMerelyRunning() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(10)
    h.engine.snooze(60)
    #expect(h.events.snoozes.isEmpty)
    #expect(h.engine.remainingUntilBreak == 90)
    #expect(h.engine.snoozesUsedToday == 0)
}

@Test @MainActor func snoozeIsIgnoredWhenStopped() {
    let h = Harness(.fast())
    h.engine.snooze(60)
    #expect(h.events.isEmpty)
}

@Test @MainActor func snoozeStopsAtTheDailyBudget() {
    var s = Settings.fast()
    s.snoozesPerDay = 1
    s.snoozesPerSession = 10
    let h = Harness(s)
    h.engine.start()
    h.run(95)
    h.engine.snooze(20)
    #expect(h.engine.snoozesRemainingToday == 0)
    h.run(20)                                     // back into pre-break
    h.clearEvents()
    h.engine.snooze(20)
    #expect(h.events.snoozes.isEmpty)
    #expect(h.engine.snoozesUsedToday == 1)
}

@Test @MainActor func snoozeStopsAtTheSessionBudget() {
    var s = Settings.fast()
    s.snoozesPerDay = 10
    s.snoozesPerSession = 2
    let h = Harness(s)
    h.engine.start()
    h.run(95)
    h.engine.snooze(20)
    h.run(20)
    h.engine.snooze(20)
    #expect(h.engine.snoozesRemainingThisSession == 0)
    h.run(20)
    h.clearEvents()
    h.engine.snooze(20)
    #expect(h.events.snoozes.isEmpty)
    #expect(h.engine.snoozesUsedThisSession == 2)
}

@Test @MainActor func snoozePreservesTheBreakKind() {
    var s = Settings.fast()
    s.longBreakEvery = 1
    let h = Harness(s)
    h.engine.start()
    h.run(95)
    h.engine.snooze(30)
    #expect(h.events.snoozes.first?.0 == .long)
    #expect(h.engine.nextBreakKind == .long)
}

// MARK: - Skip

@Test @MainActor func casualCanSkipFromThePreBreakCard() {
    var s = Settings.fast()
    s.enforcement = .casual
    let h = Harness(s)
    h.engine.start()
    h.run(95)
    #expect(h.engine.canSkipNow)
    h.clearEvents()
    h.engine.skipBreak()
    #expect(h.events.skips == [.short])
    #expect(h.engine.phase == .running(nextBreak: .short, remaining: 100))
}

@Test @MainActor func casualCanSkipDuringTheBreakImmediately() {
    var s = Settings.fast()
    s.enforcement = .casual
    let h = Harness(s)
    h.engine.start()
    h.run(100)
    #expect(h.engine.canSkipNow)
    h.clearEvents()
    h.engine.skipBreak()
    #expect(h.events.breakEndings.first?.1 == false)
    #expect(h.events.skips == [.short])
}

@Test @MainActor func balancedCannotSkipUntilTheDelayHasElapsed() {
    var s = Settings.fast()
    s.enforcement = .balanced
    s.balancedSkipDelaySeconds = 5
    let h = Harness(s)
    h.engine.start()
    h.run(100)
    #expect(!h.engine.canSkipNow)
    h.run(4)
    #expect(!h.engine.canSkipNow)
    h.engine.skipBreak()
    #expect(h.engine.phase.kindValue == .short)
    #expect(h.engine.phase == .inBreak(kind: .short, remaining: 6, total: 10))
    h.run(1)
    #expect(h.engine.canSkipNow)
    h.engine.skipBreak()
    #expect(h.engine.phase.isRunning)
}

@Test @MainActor func balancedCanAlwaysSkipFromThePreBreakCard() {
    var s = Settings.fast()
    s.enforcement = .balanced
    let h = Harness(s)
    h.engine.start()
    h.run(95)
    #expect(h.engine.canSkipNow)
}

@Test @MainActor func hardcoreNeverAllowsSkipping() {
    var s = Settings.fast()
    s.enforcement = .hardcore
    let h = Harness(s)
    h.engine.start()
    h.run(95)
    #expect(!h.engine.canSkipNow)
    h.run(10)                                     // now in the break
    #expect(h.engine.phase.kindValue == .short)
    #expect(!h.engine.canSkipNow)
    h.clearEvents()
    h.engine.skipBreak()
    #expect(h.events.skips.isEmpty)
}

@Test @MainActor func skippingRestartsTheIntervalWithoutAdvancingTheCycle() {
    var s = Settings.fast()
    s.enforcement = .casual
    let h = Harness(s)
    h.engine.start()
    h.run(100)
    h.engine.skipBreak()
    #expect(h.engine.shortBreaksSinceLong == 0)
    #expect(h.engine.remainingUntilBreak == 100)
}

@Test @MainActor func skippingALongBreakLeavesTheNextBreakLong() {
    var s = Settings.fast()
    s.enforcement = .casual
    s.longBreakEvery = 2
    let h = Harness(s)
    h.engine.start()
    h.run(110)                                    // short break completed -> next is long
    #expect(h.engine.nextBreakKind == .long)
    h.run(100)                                    // long break starts
    h.engine.skipBreak()
    #expect(h.engine.nextBreakKind == .long)
    #expect(h.engine.shortBreaksSinceLong == 1)
    #expect(h.engine.phase == .running(nextBreak: .long, remaining: 100))
}

@Test @MainActor func skippingDoesNotRefundSessionSnoozes() {
    var s = Settings.fast()
    s.enforcement = .casual
    let h = Harness(s)
    h.engine.start()
    h.run(95)
    h.engine.snooze(20)
    h.run(20)
    h.engine.skipBreak()
    #expect(h.engine.snoozesUsedThisSession == 1)
}

// MARK: - End break early

@Test @MainActor func endBreakEarlyIsRefusedBeforeTheAllowedFraction() {
    var s = Settings.fast()
    s.allowEndBreakEarlyAfterFraction = 0.8
    let h = Harness(s)
    h.engine.start()
    h.run(100)
    h.run(5)                                      // 50% elapsed
    #expect(!h.engine.canEndBreakEarly)
    h.clearEvents()
    h.engine.endBreakEarly()
    #expect(h.events.breakEndings.isEmpty)
}

@Test @MainActor func endBreakEarlyAfterTheFractionCountsAsCompleted() {
    var s = Settings.fast()
    s.allowEndBreakEarlyAfterFraction = 0.8
    let h = Harness(s)
    h.engine.start()
    h.run(100)
    h.run(8)                                      // 80% elapsed
    #expect(h.engine.canEndBreakEarly)
    h.clearEvents()
    h.engine.endBreakEarly()
    #expect(h.events.breakEndings.first?.1 == true)
    #expect(h.engine.shortBreaksSinceLong == 1)
    #expect(h.engine.phase == .running(nextBreak: .short, remaining: 100))
}

@Test @MainActor func endBreakEarlyIsANoOpOutsideABreak() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(50)
    #expect(!h.engine.canEndBreakEarly)
    h.engine.endBreakEarly()
    #expect(h.engine.phase.isRunning)
}

// MARK: - Break on demand

@Test @MainActor func startBreakNowStartsTheRequestedKind() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(10)
    h.engine.startBreakNow(.long)
    #expect(h.engine.phase == .inBreak(kind: .long, remaining: 20, total: 20))
    #expect(h.events.breakStarts.first?.0 == .long)
}

@Test @MainActor func startBreakNowWorksWhilePaused() {
    let h = Harness(.fast())
    h.engine.start()
    h.engine.updatePauseReasons([.zoomMeeting])
    h.engine.startBreakNow(.short)
    #expect(h.engine.phase.kindValue == .short)
    #expect(h.engine.phase.isInBreak)
    h.run(10)
    #expect(h.events.breakEndings.first?.1 == true)
    #expect(h.engine.phase.isPaused)              // back to the meeting pause afterwards
}

@Test @MainActor func startBreakNowIsIgnoredWhileAlreadyInABreak() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(100)
    h.clearEvents()
    h.engine.startBreakNow(.long)
    #expect(h.events.breakStarts.isEmpty)
}

@Test @MainActor func startCustomBreakUsesTheGivenDuration() {
    let h = Harness(.fast())
    h.engine.start()
    h.engine.startCustomBreak(duration: 45)
    #expect(h.engine.phase == .inBreak(kind: .short, remaining: 45, total: 45))
    h.run(45)
    #expect(h.events.breakEndings.first?.1 == true)
}

@Test @MainActor func startCustomBreakRejectsNonPositiveDurations() {
    let h = Harness(.fast())
    h.engine.start()
    h.engine.startCustomBreak(duration: 0)
    #expect(h.engine.phase.isRunning)
}

// MARK: - Add time

@Test @MainActor func addMinuteAddsSixtySeconds() {
    let h = Harness()
    h.engine.start()
    h.run(100)
    h.engine.addMinute()
    #expect(h.engine.remainingUntilBreak == 1160)
}

@Test @MainActor func addMinuteFromPreBreakReturnsToRunning() {
    let h = Harness()
    h.engine.start()
    h.run(1170)                                   // remaining 30, pre-break
    #expect(h.engine.phase.isPreBreak)
    h.engine.addMinute()
    #expect(h.engine.phase == .running(nextBreak: .short, remaining: 90))
    h.clearEvents()
    h.run(30)                                     // crosses the 60s threshold again
    #expect(h.events.preBreakWarnings.count == 1) // the card is offered again
}

@Test @MainActor func addMinuteThatStaysInsideTheWarningWindowKeepsTheCard() {
    var s = Settings()
    s.preBreakWarningSeconds = 120
    let h = Harness(s)
    h.engine.start()
    h.run(1150)                                   // remaining 50, inside a 120s window
    #expect(h.engine.phase.isPreBreak)
    h.engine.addMinute()
    #expect(h.engine.phase == .preBreak(kind: .short, remaining: 110))
}

@Test @MainActor func addMinuteIsIgnoredDuringABreak() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(100)
    h.engine.addMinute()
    #expect(h.engine.phase == .inBreak(kind: .short, remaining: 10, total: 10))
}

// MARK: - Typing / dragging deferral

@Test @MainActor func aDueBreakWaitsForTypingToStop() {
    var s = Settings.fast()
    s.deferWhileTyping = true
    s.typingBufferSeconds = 3
    let h = Harness(s)
    h.engine.start()
    h.engine.updateActivityHint(.typing)
    h.run(100)
    #expect(h.engine.phase == .waitingForActivityToStop(kind: .short, hint: .typing))
    #expect(h.events.breakStarts.isEmpty)
    h.run(30)
    #expect(h.events.breakStarts.isEmpty)         // still typing, still waiting
}

@Test @MainActor func theBreakStartsAfterTheTypingBuffer() {
    var s = Settings.fast()
    s.deferWhileTyping = true
    s.typingBufferSeconds = 3
    let h = Harness(s)
    h.engine.start()
    h.engine.updateActivityHint(.dragging)
    h.run(100)
    #expect(h.engine.phase == .waitingForActivityToStop(kind: .short, hint: .dragging))
    h.engine.updateActivityHint(nil)
    h.run(2)
    #expect(h.events.breakStarts.isEmpty)
    h.run(1)
    #expect(h.events.breakStarts.count == 1)
    #expect(h.engine.phase.isInBreak)
}

@Test @MainActor func typingThatResumesRestartsTheBuffer() {
    var s = Settings.fast()
    s.deferWhileTyping = true
    s.typingBufferSeconds = 3
    let h = Harness(s)
    h.engine.start()
    h.engine.updateActivityHint(.typing)
    h.run(100)
    h.engine.updateActivityHint(nil)
    h.run(2)
    h.engine.updateActivityHint(.typing)          // started typing again
    h.run(2)
    #expect(h.events.breakStarts.isEmpty)
    h.engine.updateActivityHint(nil)
    h.run(3)
    #expect(h.events.breakStarts.count == 1)
}

@Test @MainActor func deferralOffStartsTheBreakDespiteTyping() {
    var s = Settings.fast()
    s.deferWhileTyping = false
    let h = Harness(s)
    h.engine.start()
    h.engine.updateActivityHint(.typing)
    h.run(100)
    #expect(h.engine.phase.isInBreak)
}

@Test @MainActor func activityHintsDoNotDelayAnythingEarlyInTheInterval() {
    var s = Settings.fast()
    s.deferWhileTyping = true
    let h = Harness(s)
    h.engine.start()
    h.engine.updateActivityHint(.dictating)
    h.run(50)
    #expect(h.engine.phase == .running(nextBreak: .short, remaining: 50))
}
