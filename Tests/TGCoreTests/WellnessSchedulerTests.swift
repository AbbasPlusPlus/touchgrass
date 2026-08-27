// The app's second clock: blink/posture nudges run on real time, not on screen time.

import Foundation
import Combine
import Testing
@testable import TGCore

@MainActor
private final class WellnessHarness {
    let clock = FakeClock()
    let scheduler: WellnessScheduler
    private(set) var events: [EngineEvent] = []
    private var bag = Set<AnyCancellable>()

    init(_ settings: Settings) {
        scheduler = WellnessScheduler(settings: settings, clock: clock)
        scheduler.events.sink { [weak self] event in self?.events.append(event) }.store(in: &bag)
    }

    func run(_ seconds: TimeInterval, isInBreak: Bool = false, step: TimeInterval = 1) {
        var left = seconds
        while left > 0 {
            let chunk = Swift.min(step, left)
            clock.advance(chunk)
            scheduler.tick(isInBreak: isInBreak)
            left -= chunk
        }
    }

    func jump(_ seconds: TimeInterval, isInBreak: Bool = false) {
        clock.advance(seconds)
        scheduler.tick(isInBreak: isInBreak)
    }

    func clearEvents() { events.removeAll() }
}

private func wellnessSettings(blink: TimeInterval? = nil, posture: TimeInterval? = nil) -> Settings {
    var s = Settings()
    if let blink {
        s.blinkRemindersEnabled = true
        s.blinkReminderInterval = blink
    }
    if let posture {
        s.postureRemindersEnabled = true
        s.postureReminderInterval = posture
    }
    return s
}

// MARK: -

@Test @MainActor func wellnessIsSilentWhenDisabled() {
    let h = WellnessHarness(Settings())
    h.scheduler.start()
    h.run(3600)
    #expect(h.events.isEmpty)
    #expect(h.scheduler.nextBlinkIn == nil)
    #expect(h.scheduler.nextPostureIn == nil)
}

@Test @MainActor func wellnessIsSilentUntilStarted() {
    let h = WellnessHarness(wellnessSettings(blink: 60))
    h.run(600)
    #expect(h.events.isEmpty)
}

@Test @MainActor func blinkFiresOnItsInterval() {
    let h = WellnessHarness(wellnessSettings(blink: 60))
    h.scheduler.start()
    h.run(59)
    #expect(h.events.isEmpty)
    h.run(1)
    #expect(h.events.wellnessKinds == [.blink])
    h.run(60)
    #expect(h.events.wellnessKinds == [.blink, .blink])
}

@Test @MainActor func postureFiresIndependentlyOfBlink() {
    let h = WellnessHarness(wellnessSettings(blink: 60, posture: 90))
    h.scheduler.start()
    h.run(180)
    #expect(h.events.wellnessKinds.filter { $0 == .blink }.count == 3)
    #expect(h.events.wellnessKinds.filter { $0 == .posture }.count == 2)
}

@Test @MainActor func onlyTheEnabledRemindersFire() {
    let h = WellnessHarness(wellnessSettings(posture: 30))
    h.scheduler.start()
    h.run(120)
    #expect(h.events.wellnessKinds.allSatisfy { $0 == .posture })
    #expect(h.events.wellnessKinds.count == 4)
}

@Test @MainActor func wellnessUsesWallClockAndDoesNotBurstAfterAJump() {
    let h = WellnessHarness(wellnessSettings(blink: 60))
    h.scheduler.start()
    h.jump(600)                                  // ten intervals in one tick
    #expect(h.events.wellnessKinds == [.blink])  // one nudge, not ten
    #expect(h.scheduler.nextBlinkIn == 60)       // and the counter restarts cleanly
}

@Test @MainActor func wellnessKeepsRunningWhileTheBreakEngineIsPaused() {
    // Deliberate asymmetry: a meeting freezes break timing but not blink timing.
    let h = WellnessHarness(wellnessSettings(blink: 60))
    h.scheduler.start()
    h.run(120, isInBreak: false)
    #expect(h.events.wellnessKinds.count == 2)
}

@Test @MainActor func wellnessIsFrozenDuringABreak() {
    let h = WellnessHarness(wellnessSettings(blink: 60))
    h.scheduler.start()
    h.run(50)
    h.run(300, isInBreak: true)
    #expect(h.events.isEmpty)
    #expect(h.scheduler.nextBlinkIn == 10)
    h.run(10)
    #expect(h.events.wellnessKinds == [.blink])
}

@Test @MainActor func resetAfterBreakPutsAFullIntervalBack() {
    let h = WellnessHarness(wellnessSettings(blink: 60, posture: 90))
    h.scheduler.start()
    h.run(55)
    h.scheduler.resetAfterBreak()
    #expect(h.scheduler.nextBlinkIn == 60)
    #expect(h.scheduler.nextPostureIn == 90)
    h.run(59)
    #expect(h.events.isEmpty)
    h.run(1)
    #expect(h.events.wellnessKinds == [.blink])
}

@Test @MainActor func stoppingHaltsAndResetsTheCounters() {
    let h = WellnessHarness(wellnessSettings(blink: 60))
    h.scheduler.start()
    h.run(50)
    h.scheduler.stop()
    #expect(!h.scheduler.isRunning)
    h.run(600)
    #expect(h.events.isEmpty)
    h.scheduler.start()
    h.run(59)
    #expect(h.events.isEmpty)
    h.run(1)
    #expect(h.events.wellnessKinds == [.blink])
}

@Test @MainActor func nextBlinkInCountsDown() {
    let h = WellnessHarness(wellnessSettings(blink: 60))
    h.scheduler.start()
    #expect(h.scheduler.nextBlinkIn == 60)
    h.run(20)
    #expect(h.scheduler.nextBlinkIn == 40)
}

@Test @MainActor func enablingAReminderMidFlightStartsAFullInterval() {
    let h = WellnessHarness(wellnessSettings(blink: 60))
    h.scheduler.start()
    h.run(30)
    h.scheduler.settings.postureRemindersEnabled = true
    h.scheduler.settings.postureReminderInterval = 45
    #expect(h.scheduler.nextPostureIn == 45)
    h.run(45)
    #expect(h.events.wellnessKinds.contains(.posture))
}

@Test @MainActor func changingAnIntervalShiftsRatherThanRestarts() {
    let h = WellnessHarness(wellnessSettings(blink: 600))
    h.scheduler.start()
    h.run(100)                                   // 500 left
    h.scheduler.settings.blinkReminderInterval = 900
    #expect(h.scheduler.nextBlinkIn == 800)
    h.scheduler.settings.blinkReminderInterval = 300
    #expect(h.scheduler.nextBlinkIn == 200)
}

@Test @MainActor func shrinkingAnIntervalBelowTheRemainderClampsIt() {
    let h = WellnessHarness(wellnessSettings(blink: 600))
    h.scheduler.start()
    h.scheduler.settings.blinkReminderInterval = 60
    #expect(h.scheduler.nextBlinkIn == 60)
}
