// Lifecycle, wall-clock timing, focus-time accounting, long-break cadence, pre-break signals.

import Foundation
import Testing
@testable import TGCore

// MARK: - Lifecycle

@Test @MainActor func startEntersRunningWithAFullInterval() {
    let h = Harness()
    h.engine.start()
    #expect(h.engine.phase == .running(nextBreak: .short, remaining: 1200))
}

@Test @MainActor func stopReturnsToStopped() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(50)
    h.engine.stop()
    #expect(h.engine.phase.isStopped)
}

@Test @MainActor func tickBeforeStartDoesNothing() {
    let h = Harness(.fast())
    h.run(500)
    #expect(h.engine.phase.isStopped)
    #expect(h.events.isEmpty)
}

@Test @MainActor func tickAfterStopDoesNotAdvance() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(10)
    h.engine.stop()
    h.clearEvents()
    h.run(500)
    #expect(h.events.isEmpty)
    #expect(h.engine.phase.isStopped)
}

@Test @MainActor func restartResetsTheInterval() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(60)
    h.engine.start()
    #expect(h.engine.remainingUntilBreak == 100)
    #expect(h.engine.currentSessionFocusTime == 0)
}

// MARK: - Wall clock, not tick counts

@Test @MainActor func remainingUsesWallClockDeltaNotTickCount() {
    let h = Harness()
    h.engine.start()
    // One tick, ten minutes of wall clock.
    h.jump(600)
    #expect(h.engine.remainingUntilBreak == 600)
}

@Test @MainActor func coarseTicksAndFineTicksAgree() {
    let coarse = Harness()
    coarse.engine.start()
    coarse.run(300, step: 60)

    let fine = Harness()
    fine.engine.start()
    fine.run(300, step: 1)

    #expect(coarse.engine.remainingUntilBreak == fine.engine.remainingUntilBreak)
}

@Test @MainActor func aTickAfterHalfAnHourOfSleepGoesStraightToTheBreak() {
    let h = Harness()
    h.engine.start()
    h.jump(1800)   // 30 min in one tick: past the 20 min deadline
    #expect(h.events.breakStarts.count == 1)
    #expect(h.events.preBreakWarnings.isEmpty)
    #expect(h.events.countdownSeconds.isEmpty)   // no phantom countdown spam
}

// MARK: - Focus time accounting

@Test @MainActor func focusTimeAccruesWhileRunning() {
    let h = Harness()
    h.engine.start()
    h.run(300)
    #expect(h.engine.currentSessionFocusTime == 300)
}

@Test @MainActor func focusTimeAccruesDuringPreBreak() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(95)
    #expect(h.engine.phase.isPreBreak)
    #expect(h.engine.currentSessionFocusTime == 95)
}

@Test @MainActor func focusTimeFreezesWhilePaused() {
    let h = Harness()
    h.engine.start()
    h.run(120)
    h.engine.updatePauseReasons([.zoomMeeting])
    h.run(600)
    #expect(h.engine.currentSessionFocusTime == 120)
    #expect(h.engine.remainingUntilBreak == 1080)
}

@Test @MainActor func focusTimeFreezesDuringABreak() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(100)                       // break starts
    let atBreakStart = h.engine.currentSessionFocusTime
    h.run(5)
    #expect(h.engine.currentSessionFocusTime == atBreakStart)
}

@Test @MainActor func focusTimeFreezesWhenStopped() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(20)
    h.engine.stop()
    h.run(100)
    #expect(h.engine.currentSessionFocusTime == 20)
}

@Test @MainActor func focusTimeAccruesWhileWaitingForTypingToStop() {
    var s = Settings.fast()
    s.deferWhileTyping = true
    let h = Harness(s)
    h.engine.start()
    h.engine.updateActivityHint(.typing)
    h.run(100)
    #expect(h.engine.phase.isWaitingForActivity)
    h.run(5)
    #expect(h.engine.currentSessionFocusTime == 105)
}

@Test @MainActor func completedBreakResetsSessionFocusTime() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(110)                       // interval + break
    #expect(h.engine.currentSessionFocusTime == 0)
}

// MARK: - Long-break cadence

@Test @MainActor func firstBreakIsShort() {
    let h = Harness(.fast())
    h.engine.start()
    #expect(h.engine.nextBreakKind == .short)
    h.run(100)
    #expect(h.events.breakStarts.first?.0 == .short)
}

@Test @MainActor func everyThirdBreakIsLong() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(110)                                   // break 1 (short) completes
    #expect(h.engine.shortBreaksSinceLong == 1)
    #expect(h.engine.nextBreakKind == .short)
    h.run(110)                                   // break 2 (short) completes
    #expect(h.engine.shortBreaksSinceLong == 2)
    #expect(h.engine.nextBreakKind == .long)
    h.clearEvents()
    h.run(100)
    #expect(h.events.breakStarts.first?.0 == .long)
    #expect(h.events.breakStarts.first?.1 == 20)  // longBreakDuration
}

@Test @MainActor func completingALongBreakResetsTheCycle() {
    var s = Settings.fast()
    s.longBreakEvery = 2
    let h = Harness(s)
    h.engine.start()
    h.run(110)                                   // short completes -> next is long
    #expect(h.engine.nextBreakKind == .long)
    h.run(120)                                   // long completes (interval 100 + duration 20)
    #expect(h.engine.shortBreaksSinceLong == 0)
    #expect(h.engine.nextBreakKind == .short)
}

@Test @MainActor func longBreaksDisabledMeansAlwaysShort() {
    var s = Settings.fast()
    s.longBreaksEnabled = false
    s.longBreakEvery = 2
    let h = Harness(s)
    h.engine.start()
    h.run(110)
    h.run(110)
    h.run(110)
    #expect(h.engine.nextBreakKind == .short)
    #expect(h.events.breakStarts.allSatisfy { $0.0 == .short })
}

@Test @MainActor func togglingLongBreaksRecomputesTheNextKind() {
    var s = Settings.fast()
    s.longBreakEvery = 2
    let h = Harness(s)
    h.engine.start()
    h.run(110)
    #expect(h.engine.nextBreakKind == .long)
    h.engine.settings.longBreaksEnabled = false
    #expect(h.engine.nextBreakKind == .short)
}

// MARK: - Day rollover

@Test @MainActor func calendarDayRolloverResetsSnoozesAndTheLongBreakCycle() {
    var s = Settings.fast()
    s.longBreakEvery = 2
    let h = Harness(s)
    h.engine.start()
    h.run(110)                                   // one short break completed
    #expect(h.engine.shortBreaksSinceLong == 1)
    h.run(90)                                    // into pre-break
    h.engine.snooze(30)
    #expect(h.engine.snoozesUsedToday == 1)

    h.engine.updatePauseReasons([.xcodeFullscreen])   // freeze so the jump doesn't fire a break
    h.jump(24 * 3600)

    #expect(h.engine.snoozesUsedToday == 0)
    #expect(h.engine.shortBreaksSinceLong == 0)
    #expect(h.engine.nextBreakKind == .short)
}

@Test @MainActor func dayRolloverIsHandledEvenWhileStopped() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(95)
    h.engine.snooze(30)
    h.engine.stop()
    #expect(h.engine.snoozesUsedToday == 1)
    h.jump(24 * 3600)
    #expect(h.engine.snoozesUsedToday == 0)
}

// MARK: - Pre-break signals

@Test @MainActor func preBreakWarningFiresOnceAtTheThreshold() {
    let h = Harness()
    h.engine.start()
    h.run(1139)
    #expect(h.events.preBreakWarnings.isEmpty)
    #expect(h.engine.phase.isRunning)
    h.run(1)
    #expect(h.events.preBreakWarnings.count == 1)
    #expect(h.events.first == .preBreakWarning(kind: .short, startsIn: 60))
    #expect(h.engine.phase == .preBreak(kind: .short, remaining: 60))
    h.run(30)
    #expect(h.events.preBreakWarnings.count == 1)   // still exactly once
}

@Test @MainActor func countdownEmitsOncePerIntegerSecond() {
    let h = Harness()
    h.engine.start()
    h.run(1199)
    #expect(h.events.countdownSeconds == [10, 9, 8, 7, 6, 5, 4, 3, 2, 1])
}

@Test @MainActor func countdownIsNotEmittedAboveTheCursorThreshold() {
    let h = Harness()
    h.engine.start()
    h.run(1150)                                  // remaining 50: warning shown, pill not yet
    #expect(h.events.preBreakWarnings.count == 1)
    #expect(h.events.countdownSeconds.isEmpty)
}

@Test @MainActor func countdownDoesNotRepeatWithinTheSameSecond() {
    let h = Harness()
    h.engine.start()
    h.run(1195)
    h.clearEvents()
    h.run(0.9, step: 0.3)                        // three ticks, still second "5" -> "5" already sent
    #expect(h.events.countdownSeconds.isEmpty)
    h.run(0.2, step: 0.2)                        // now crosses into second 4
    #expect(h.events.countdownSeconds == [4])
}

// MARK: - Break run

@Test @MainActor func breakStartsAtZeroAndEmitsBreakStarted() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(100)
    #expect(h.events.breakStarts.count == 1)
    #expect(h.engine.phase == .inBreak(kind: .short, remaining: 10, total: 10))
}

@Test @MainActor func breakEmitsATickPerTick() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(100)
    h.clearEvents()
    h.run(4)
    #expect(h.events.breakTickCount == 4)
    #expect(h.engine.phase == .inBreak(kind: .short, remaining: 6, total: 10))
}

@Test @MainActor func breakCompletesAndReturnsToRunningWithAFreshInterval() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(100)
    h.clearEvents()
    h.run(10)
    #expect(h.events.breakEndings.count == 1)
    #expect(h.events.breakEndings.first?.1 == true)
    #expect(h.engine.phase == .running(nextBreak: .short, remaining: 100))
}

@Test @MainActor func completedBreakResetsSessionSnoozes() {
    var s = Settings.fast()
    s.snoozesPerSession = 2
    let h = Harness(s)
    h.engine.start()
    h.run(95)
    h.engine.snooze(20)
    #expect(h.engine.snoozesUsedThisSession == 1)
    h.run(25)                                    // back to the deadline
    h.run(10)                                    // break runs out
    #expect(h.engine.snoozesUsedThisSession == 0)
    #expect(h.engine.snoozesUsedToday == 1)      // the daily budget is not refunded
}

@Test @MainActor func longBreakUsesTheLongDuration() {
    var s = Settings.fast()
    s.longBreakEvery = 1
    let h = Harness(s)
    h.engine.start()
    #expect(h.engine.nextBreakKind == .long)
    h.run(100)
    #expect(h.engine.phase == .inBreak(kind: .long, remaining: 20, total: 20))
}

// MARK: - Settings changes mid-run

@Test @MainActor func changingTheIntervalShiftsTheDeadlineByTheDelta() {
    let h = Harness()
    h.engine.start()
    h.run(100)                                   // remaining 1100
    h.engine.settings.shortBreakInterval = 1800  // +600
    #expect(h.engine.remainingUntilBreak == 1700)
    #expect(h.engine.phase.isRunning)             // not restarted
    h.engine.settings.shortBreakInterval = 1200  // -600
    #expect(h.engine.remainingUntilBreak == 1100)
}

@Test @MainActor func shorteningTheIntervalCanPullTheCardForward() {
    let h = Harness()
    h.engine.start()
    h.run(100)                                   // remaining 1100
    h.engine.settings.shortBreakInterval = 150   // -1050 -> remaining 50
    #expect(h.engine.remainingUntilBreak == 50)
    h.run(1)
    #expect(h.engine.phase.isPreBreak)
    #expect(h.events.preBreakWarnings.count == 1)
}

@Test @MainActor func lengtheningTheIntervalOutOfPreBreakClearsTheCard() {
    let h = Harness()
    h.engine.start()
    h.run(1145)                                  // remaining 55, pre-break
    #expect(h.engine.phase.isPreBreak)
    h.engine.settings.shortBreakInterval = 1400  // +200
    #expect(h.engine.phase.isRunning)
    #expect(h.engine.remainingUntilBreak == 255)
}
