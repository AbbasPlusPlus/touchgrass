// Smart Pause: detector reasons, manual pause, idle/away decisions, screen lock, sleep/wake.

import Foundation
import Testing
@testable import TGCore

// MARK: - Detector pause reasons

@Test @MainActor func pauseReasonsFreezeTheEngineAndEmitPaused() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(10)
    h.clearEvents()
    h.engine.updatePauseReasons([.zoomMeeting])
    #expect(h.events.pausedEvents.count == 1)
    #expect(h.engine.phase == .paused(reasons: [.zoomMeeting], nextBreak: .short, remaining: 90))
    h.run(500)
    #expect(h.engine.remainingUntilBreak == 90)
}

@Test @MainActor func pausedIsEmittedOnlyWhenTheReasonSetChanges() {
    let h = Harness(.fast())
    h.engine.start()
    h.engine.updatePauseReasons([.zoomMeeting])
    h.engine.updatePauseReasons([.zoomMeeting])
    #expect(h.events.pausedEvents.count == 1)
    h.engine.updatePauseReasons([.zoomMeeting, .xcodeFullscreen])
    #expect(h.events.pausedEvents.count == 2)
    h.engine.updatePauseReasons([])
    #expect(h.events.resumedCount == 1)
}

@Test @MainActor func resumingAfterAMeetingAppliesTheCooldown() {
    var s = Settings.fast()
    s.cooldownAfterActivity = 60
    let h = Harness(s)
    h.engine.start()
    h.run(95)                                        // remaining 5, pre-break card up
    h.engine.updatePauseReasons([.zoomMeeting])
    h.run(300)
    h.clearEvents()
    h.engine.updatePauseReasons([])
    #expect(h.engine.remainingUntilBreak == 60)      // not 5: the call just ended
    #expect(h.engine.phase.isRunning)                 // card withdrawn
    #expect(h.events.breakStarts.isEmpty)
}

@Test @MainActor func resumingAfterVideoAppliesTheCooldown() {
    var s = Settings.fast()
    s.cooldownAfterActivity = 45
    let h = Harness(s)
    h.engine.start()
    h.run(98)
    h.engine.updatePauseReasons([.youtubeVideo])
    h.engine.updatePauseReasons([])
    #expect(h.engine.remainingUntilBreak == 45)
}

@Test @MainActor func cooldownNeverShortensALongerRemaining() {
    var s = Settings.fast()
    s.cooldownAfterActivity = 60
    let h = Harness(s)
    h.engine.start()
    h.run(10)                                        // remaining 90
    h.engine.updatePauseReasons([.zoomMeeting])
    h.engine.updatePauseReasons([])
    #expect(h.engine.remainingUntilBreak == 90)
}

@Test @MainActor func noCooldownForFullscreenOrDeepFocus() {
    var s = Settings.fast()
    s.cooldownAfterActivity = 60
    let h = Harness(s)
    h.engine.start()
    h.run(95)
    h.engine.updatePauseReasons([.xcodeFullscreen])
    h.engine.updatePauseReasons([])
    #expect(h.engine.remainingUntilBreak == 5)
    #expect(h.engine.phase.isPreBreak)
}

@Test @MainActor func aBreakDueWhilePausedFiresOnResume() {
    var s = Settings.fast()
    s.cooldownAfterActivity = 0
    let h = Harness(s)
    h.engine.start()
    h.run(95)                                        // remaining 5
    h.engine.updatePauseReasons([.xcodeFullscreen])
    h.engine.settings.shortBreakInterval = 95        // delta -5 -> remaining 0 while paused
    #expect(h.engine.remainingUntilBreak == 0)
    #expect(h.engine.phase.isPaused)                  // nothing fires while paused
    h.clearEvents()
    h.engine.updatePauseReasons([])
    #expect(h.events.breakStarts.count == 1)
    #expect(h.engine.phase.isInBreak)
}

@Test @MainActor func aBreakDueWhilePausedIsHeldBackByTheCooldown() {
    var s = Settings.fast()
    s.cooldownAfterActivity = 60
    let h = Harness(s)
    h.engine.start()
    h.run(95)
    h.engine.updatePauseReasons([.zoomMeeting])
    h.engine.settings.shortBreakInterval = 95        // remaining 0 while paused
    h.clearEvents()
    h.engine.updatePauseReasons([])
    #expect(h.events.breakStarts.isEmpty)
    #expect(h.engine.remainingUntilBreak == 60)
}

@Test @MainActor func pausingDuringABreakLeavesTheBreakAlone() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(100)
    h.engine.updatePauseReasons([.zoomMeeting])
    #expect(h.engine.phase == .inBreak(kind: .short, remaining: 10, total: 10))
    h.run(10)
    #expect(h.events.breakEndings.first?.1 == true)
    #expect(h.engine.phase.isPaused)
}

// MARK: - Manual pause

@Test @MainActor func manualPauseWithADeadlineExpiresOnItsOwn() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(10)
    h.engine.pauseManually(for: 300)
    #expect(h.engine.phase.isPaused)
    h.run(299)
    #expect(h.engine.phase.isPaused)
    h.run(2)
    #expect(h.engine.phase.isRunning)
    #expect(h.events.resumedCount == 1)
}

@Test @MainActor func indefiniteManualPauseNeedsAnExplicitResume() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(10)
    h.engine.pauseManually(for: nil)
    h.run(5000)
    #expect(h.engine.phase.isPaused)
    #expect(h.engine.remainingUntilBreak == 90)
    h.engine.resumeManually()
    #expect(h.engine.phase.isRunning)
    #expect(h.events.resumedCount == 1)
}

@Test @MainActor func manualResumeDoesNotClearDetectorReasons() {
    let h = Harness(.fast())
    h.engine.start()
    h.engine.pauseManually(for: nil)
    h.engine.updatePauseReasons([.zoomMeeting])
    h.engine.resumeManually()
    #expect(h.engine.phase.pauseReasonsValue == [.zoomMeeting])
}

@Test @MainActor func detectorUpdatesCannotClobberEngineOwnedReasons() {
    let h = Harness(.fast())
    h.engine.start()
    h.engine.screenDidLock()
    h.engine.updatePauseReasons([])                  // detector says "nothing to see here"
    #expect(h.engine.phase.pauseReasonsValue == [.screenLocked])
    h.engine.screenDidUnlock()
    #expect(h.engine.phase.isRunning)
}

// MARK: - Idle / away decisions

@Test @MainActor func idleBeyondTheThresholdPausesTheEngine() {
    let h = Harness()
    h.engine.start()
    h.run(120)
    h.engine.updateIdleSeconds(120)
    #expect(h.engine.phase.pauseReasonsValue == [.idle])
    #expect(h.engine.remainingUntilBreak == 1080)
}

@Test @MainActor func idleBelowTheThresholdIsIgnored() {
    let h = Harness()
    h.engine.start()
    h.run(60)
    h.engine.updateIdleSeconds(60)
    #expect(h.engine.phase.isRunning)
}

@Test @MainActor func aShortAwayResumesWithoutResettingTheTimer() {
    let h = Harness()                                 // idlePauseAfter 120, idleResetAfter 300
    h.engine.start()
    h.run(120)
    h.engine.updateIdleSeconds(120)                   // away since t=0
    h.skipTime(80)                                    // total away 200s
    h.clearEvents()
    h.engine.updateIdleSeconds(0)
    #expect(h.engine.remainingUntilBreak == 1080)     // untouched
    #expect(h.events.awayDecisions.count == 1)
    #expect(h.events.awayDecisions.first?.0 == false)
    #expect(h.events.awayDecisions.first?.1 == 200)
}

@Test @MainActor func aLongAwayCountsAsABreakAndResetsTheTimer() {
    let h = Harness()
    h.engine.start()
    h.run(120)
    h.engine.updateIdleSeconds(120)
    h.skipTime(400)                                   // total away 520s > idleResetAfter
    h.clearEvents()
    h.engine.updateIdleSeconds(0)
    #expect(h.engine.remainingUntilBreak == 1200)
    #expect(h.engine.currentSessionFocusTime == 0)
    #expect(h.events.awayDecisions.first?.0 == true)
    #expect(h.events.awayDecisions.first?.1 == 520)
    #expect(h.engine.phase.isRunning)
}

@Test @MainActor func aLongAwayDoesNotEarnALongBreak() {
    var s = Settings()
    s.longBreakEvery = 2
    let h = Harness(s)
    h.engine.start()
    h.run(120)
    h.engine.updateIdleSeconds(300)
    h.skipTime(10)
    h.engine.updateIdleSeconds(0)
    #expect(h.engine.shortBreaksSinceLong == 0)
    #expect(h.engine.nextBreakKind == .short)
}

@Test @MainActor func undoingAResetRestoresThePreAwayTimer() {
    let h = Harness()
    h.engine.start()
    h.run(120)
    h.engine.updateIdleSeconds(120)
    h.skipTime(400)
    h.engine.updateIdleSeconds(0)
    #expect(h.engine.remainingUntilBreak == 1200)
    #expect(h.engine.canUndoAwayDecision)
    h.clearEvents()
    h.engine.undoAwayDecision()
    #expect(h.engine.remainingUntilBreak == 1080)
    #expect(h.events.awayDecisions.first?.0 == false)
    #expect(!h.engine.canUndoAwayDecision)            // one flip only
}

@Test @MainActor func undoingANonResetPerformsTheResetInstead() {
    let h = Harness()
    h.engine.start()
    h.run(120)
    h.engine.updateIdleSeconds(120)
    h.skipTime(80)
    h.engine.updateIdleSeconds(0)
    #expect(h.engine.remainingUntilBreak == 1080)
    h.clearEvents()
    h.engine.undoAwayDecision()
    #expect(h.engine.remainingUntilBreak == 1200)
    #expect(h.events.awayDecisions.first?.0 == true)
}

@Test @MainActor func theUndoWindowExpires() {
    let h = Harness()
    h.engine.start()
    h.run(120)
    h.engine.updateIdleSeconds(120)
    h.skipTime(400)
    h.engine.updateIdleSeconds(0)
    h.run(31)
    #expect(!h.engine.canUndoAwayDecision)
    h.clearEvents()
    h.engine.undoAwayDecision()
    #expect(h.events.awayDecisions.isEmpty)
}

@Test @MainActor func idleThatStartsDuringABreakDoesNotDisturbIt() {
    var s = Settings.fast()
    s.shortBreakDuration = 400
    let h = Harness(s)
    h.engine.start()
    h.run(100)
    h.engine.updateIdleSeconds(150)                   // stepped away during the break
    #expect(h.engine.phase.isInBreak)
    h.run(400)                                        // break runs to completion regardless
    #expect(h.events.breakEndings.first?.1 == true)
    h.clearEvents()
    h.engine.updateIdleSeconds(0)
    #expect(h.events.awayDecisions.isEmpty)           // the break was the break
    #expect(h.engine.remainingUntilBreak == 100)
}

// MARK: - Screen lock

@Test @MainActor func lockingTheScreenPausesTheEngine() {
    let h = Harness()
    h.engine.start()
    h.run(60)
    h.engine.screenDidLock()
    #expect(h.engine.phase.pauseReasonsValue == [.screenLocked])
    h.run(600)
    #expect(h.engine.remainingUntilBreak == 1140)
}

@Test @MainActor func aQuickLockAndUnlockIsCompletelySilent() {
    let h = Harness()
    h.engine.start()
    h.run(60)
    h.engine.screenDidLock()
    h.skipTime(30)
    h.clearEvents()
    h.engine.screenDidUnlock()
    #expect(h.events.awayDecisions.isEmpty)           // no toast for a 30s blip
    #expect(h.events.resumedCount == 1)
    #expect(h.engine.remainingUntilBreak == 1140)     // and definitely no reset
}

@Test @MainActor func aLongLockCountsAsABreak() {
    let h = Harness()
    h.engine.start()
    h.run(60)
    h.engine.screenDidLock()
    h.skipTime(900)
    h.clearEvents()
    h.engine.screenDidUnlock()
    #expect(h.events.awayDecisions.first?.0 == true)
    #expect(h.events.awayDecisions.first?.1 == 900)
    #expect(h.engine.remainingUntilBreak == 1200)
}

@Test @MainActor func lockingDuringABreakKeepsTheBreakCounting() {
    let h = Harness(.fast())
    h.engine.start()
    h.run(100)
    h.engine.screenDidLock()
    #expect(h.engine.phase == .inBreak(kind: .short, remaining: 10, total: 10))
    h.run(10)
    #expect(h.events.breakEndings.first?.1 == true)
    h.clearEvents()
    h.engine.screenDidUnlock()
    #expect(h.events.awayDecisions.isEmpty)
}

@Test @MainActor func idleAndLockShareOneAwayEpisode() {
    let h = Harness()
    h.engine.start()
    h.run(150)
    h.engine.updateIdleSeconds(150)                   // away since t=0
    h.skipTime(50)
    h.engine.screenDidLock()                          // lock on top of idle
    h.skipTime(50)
    h.engine.updateIdleSeconds(0)                     // idle clears, still locked
    #expect(h.engine.phase.pauseReasonsValue == [.screenLocked])
    h.clearEvents()
    h.engine.screenDidUnlock()
    #expect(h.events.awayDecisions.count == 1)
    #expect(h.events.awayDecisions.first?.1 == 250)   // measured from the earliest source
    #expect(h.events.awayDecisions.first?.0 == false) // 250 < idleResetAfter
}

// MARK: - Sleep / wake

@Test @MainActor func wakingAfterALongSleepCountsAsTimeAway() {
    let h = Harness()
    h.engine.start()
    h.run(60)
    h.skipTime(1800)                                  // lid closed for 30 minutes
    h.clearEvents()
    h.engine.systemDidWake()
    #expect(h.events.breakStarts.isEmpty)
    #expect(h.events.countdownSeconds.isEmpty)
    #expect(h.events.awayDecisions.first?.0 == true)
    #expect(h.events.awayDecisions.first?.1 == 1800)
    #expect(h.engine.remainingUntilBreak == 1200)
}

@Test @MainActor func wakingAfterAShortSleepJustCatchesUp() {
    let h = Harness()
    h.engine.start()
    h.run(1190)                                       // remaining 10
    h.skipTime(5)
    h.clearEvents()
    h.engine.systemDidWake()
    #expect(h.engine.remainingUntilBreak == 5)
    #expect(h.events.countdownSeconds == [5])         // exactly one pill, no burst
    #expect(h.events.awayDecisions.isEmpty)
}

@Test @MainActor func wakingDuringABreakJustTicksTheBreak() {
    var s = Settings.fast()
    s.shortBreakDuration = 600
    let h = Harness(s)
    h.engine.start()
    h.run(100)
    h.skipTime(400)
    h.engine.systemDidWake()
    #expect(h.engine.phase == .inBreak(kind: .short, remaining: 200, total: 600))
    #expect(h.events.awayDecisions.isEmpty)
}

@Test @MainActor func wakingWhilePausedDoesNotMakeAnAwayDecision() {
    let h = Harness()
    h.engine.start()
    h.run(60)
    h.engine.updatePauseReasons([.zoomMeeting])
    h.skipTime(1800)
    h.clearEvents()
    h.engine.systemDidWake()
    #expect(h.events.awayDecisions.isEmpty)
    #expect(h.engine.remainingUntilBreak == 1140)
}

@Test @MainActor func aSleepAwayDecisionCanBeUndone() {
    let h = Harness()
    h.engine.start()
    h.run(60)
    h.skipTime(1800)
    h.engine.systemDidWake()
    #expect(h.engine.remainingUntilBreak == 1200)
    h.engine.undoAwayDecision()
    #expect(h.engine.remainingUntilBreak == 1140)
}
