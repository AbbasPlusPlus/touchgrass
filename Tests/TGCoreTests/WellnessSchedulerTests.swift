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

// MARK: - Custom reminders

private func customSettings(_ reminders: CustomReminder...) -> Settings {
    var s = Settings()
    s.customReminders = reminders
    return s
}

private func water(_ interval: TimeInterval, enabled: Bool = true, id: UUID = UUID()) -> CustomReminder {
    CustomReminder(id: id, title: "Drink water", symbol: "drop.fill", interval: interval, enabled: enabled)
}

private func stretch(_ interval: TimeInterval, enabled: Bool = true, id: UUID = UUID()) -> CustomReminder {
    CustomReminder(id: id, title: "Stretch", symbol: "figure.cooldown", interval: interval, enabled: enabled)
}

@Test @MainActor func customReminderFiresOnItsIntervalWithItsOwnCopy() {
    let h = WellnessHarness(customSettings(water(60)))
    h.scheduler.start()
    h.run(59)
    #expect(h.events.isEmpty)
    h.run(1)
    #expect(h.events.customReminders.count == 1)
    #expect(h.events.customReminders.first?.title == "Drink water")
    #expect(h.events.customReminders.first?.symbol == "drop.fill")
    h.run(60)
    #expect(h.events.customReminderTitles == ["Drink water", "Drink water"])
}

@Test @MainActor func disabledCustomRemindersNeverFire() {
    let h = WellnessHarness(customSettings(water(60, enabled: false)))
    h.scheduler.start()
    h.run(600)
    #expect(h.events.isEmpty)
    #expect(h.scheduler.nextCustomIn == nil)
}

@Test @MainActor func customRemindersRunIndependentlyOfEachOtherAndOfBlink() {
    var s = customSettings(water(60), stretch(90))
    s.blinkRemindersEnabled = true
    s.blinkReminderInterval = 45
    let h = WellnessHarness(s)
    h.scheduler.start()
    h.run(180)
    #expect(h.events.customReminderTitles.filter { $0 == "Drink water" }.count == 3)
    #expect(h.events.customReminderTitles.filter { $0 == "Stretch" }.count == 2)
    #expect(h.events.wellnessKinds.count == 4)
}

@Test @MainActor func customRemindersUseWallClockAndDoNotBurstAfterAJump() {
    let h = WellnessHarness(customSettings(water(60)))
    h.scheduler.start()
    h.jump(600)
    #expect(h.events.customReminders.count == 1)
    #expect(h.scheduler.nextCustomIn == 60)
}

@Test @MainActor func customRemindersFreezeDuringABreakAndResetAfterOne() {
    let h = WellnessHarness(customSettings(water(60)))
    h.scheduler.start()
    h.run(50)
    h.run(300, isInBreak: true)
    #expect(h.events.isEmpty)
    #expect(h.scheduler.nextCustomIn == 10)

    h.scheduler.resetAfterBreak()
    #expect(h.scheduler.nextCustomIn == 60)
    h.run(59)
    #expect(h.events.isEmpty)
    h.run(1)
    #expect(h.events.customReminders.count == 1)
}

@Test @MainActor func nextCustomInIsTheSoonestEnabledReminder() {
    let h = WellnessHarness(customSettings(water(600), stretch(120), CustomReminder(title: "Eye drops", interval: 30, enabled: false)))
    h.scheduler.start()
    #expect(h.scheduler.nextCustomIn == 120)
    h.run(20)
    #expect(h.scheduler.nextCustomIn == 100)
}

@Test @MainActor func addingAReminderMidFlightStartsAFullIntervalAndLeavesOthersAlone() {
    let waterID = UUID()
    let h = WellnessHarness(customSettings(water(600, id: waterID)))
    h.scheduler.start()
    h.run(100)                                             // water: 500 left
    h.scheduler.settings.customReminders.append(stretch(60))
    h.run(60)
    #expect(h.events.customReminderTitles == ["Stretch"])   // the newcomer, not water
}

@Test @MainActor func removingAReminderStopsIt() {
    let waterID = UUID()
    let h = WellnessHarness(customSettings(water(60, id: waterID)))
    h.scheduler.start()
    h.run(30)
    h.scheduler.settings.customReminders = []
    h.run(600)
    #expect(h.events.isEmpty)
    #expect(h.scheduler.nextCustomIn == nil)
}

@Test @MainActor func changingACustomIntervalShiftsRatherThanRestarts() {
    let waterID = UUID()
    let h = WellnessHarness(customSettings(water(600, id: waterID)))
    h.scheduler.start()
    h.run(100)                                             // 500 left
    h.scheduler.settings.customReminders[0].interval = 900
    #expect(h.scheduler.nextCustomIn == 800)
    h.scheduler.settings.customReminders[0].interval = 300
    #expect(h.scheduler.nextCustomIn == 200)
    // Shrinking below the delta lands on zero (same shift-and-clamp rule as blink/posture):
    // the reminder is overdue, so it fires on the next tick rather than being lost.
    h.scheduler.settings.customReminders[0].interval = 60
    #expect(h.scheduler.nextCustomIn == 0)
    h.run(1)
    #expect(h.events.customReminders.count == 1)
    #expect(h.scheduler.nextCustomIn == 60)
}

@Test @MainActor func switchingAReminderOnStartsAFullInterval() {
    let waterID = UUID()
    let h = WellnessHarness(customSettings(water(60, enabled: false, id: waterID)))
    h.scheduler.start()
    h.run(50)
    h.scheduler.settings.customReminders[0].enabled = true
    #expect(h.scheduler.nextCustomIn == 60)
    h.run(59)
    #expect(h.events.isEmpty)
    h.run(1)
    #expect(h.events.customReminders.count == 1)
}

@Test @MainActor func renamingAReminderDoesNotResetItsCountdown() {
    let waterID = UUID()
    let h = WellnessHarness(customSettings(water(60, id: waterID)))
    h.scheduler.start()
    h.run(50)
    h.scheduler.settings.customReminders[0].title = "Hydrate"
    #expect(h.scheduler.nextCustomIn == 10)
    h.run(10)
    #expect(h.events.customReminderTitles == ["Hydrate"])
}

@Test @MainActor func blankTitlesAndSymbolsFallBackToSomethingDrawable() {
    let h = WellnessHarness(customSettings(CustomReminder(title: "   ", symbol: "  ", interval: 30, enabled: true)))
    h.scheduler.start()
    h.run(30)
    #expect(h.events.customReminders.first?.title == CustomReminder.defaultTitle)
    #expect(h.events.customReminders.first?.symbol == CustomReminder.defaultSymbol)
}

@Test @MainActor func aZeroIntervalReminderIsIgnored() {
    let h = WellnessHarness(customSettings(CustomReminder(title: "Broken", interval: 0, enabled: true)))
    h.scheduler.start()
    h.run(600)
    #expect(h.events.isEmpty)
    #expect(h.scheduler.nextCustomIn == nil)
}

@Test @MainActor func stoppingHaltsCustomReminders() {
    let h = WellnessHarness(customSettings(water(60)))
    h.scheduler.start()
    h.run(50)
    h.scheduler.stop()
    h.run(600)
    #expect(h.events.isEmpty)
    #expect(h.scheduler.nextCustomIn == nil)
}
