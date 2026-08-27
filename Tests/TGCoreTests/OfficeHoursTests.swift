// Office hours: the window arithmetic (including past-midnight shifts and day filtering) and the
// engine behaviour around it — pausing outside, a fresh interval on the way back in, and a break
// that is already on screen when the window closes.

import Foundation
import Testing
@testable import TGCore

// MARK: - Fixtures

/// A fixed week so weekday numbers are unambiguous: Sunday 24 Aug 2025 … Saturday 30 Aug 2025.
private func at(_ weekday: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var parts = DateComponents()
    parts.year = 2025
    parts.month = 8
    parts.day = 23 + weekday          // weekday 1 (Sun) → the 24th
    parts.hour = hour
    parts.minute = minute
    return Calendar.current.date(from: parts) ?? Date()
}

private let sunday = 1
private let monday = 2
private let tuesday = 3
private let saturday = 7

private let weekdays: Set<Int> = [2, 3, 4, 5, 6]

/// 09:00–18:00, Monday to Friday, on top of the fast test settings.
private func officeSettings() -> Settings {
    var s = Settings.fast()
    s.officeHoursEnabled = true
    s.officeHoursStart = 9 * 60
    s.officeHoursEnd = 18 * 60
    s.officeDays = weekdays
    return s
}

// MARK: - The window

@Test func middayOnAWorkingDayIsInsideTheWindow() {
    #expect(OfficeHours.contains(at(monday, 12), start: 9 * 60, end: 18 * 60, days: weekdays))
}

@Test func beforeStartAndAfterEndAreOutside() {
    #expect(!OfficeHours.contains(at(monday, 8, 59), start: 9 * 60, end: 18 * 60, days: weekdays))
    #expect(!OfficeHours.contains(at(monday, 18, 1), start: 9 * 60, end: 18 * 60, days: weekdays))
}

@Test func boundariesAreHalfOpenSoTheEndMinuteIsAlreadyOutside() {
    #expect(OfficeHours.contains(at(monday, 9, 0), start: 9 * 60, end: 18 * 60, days: weekdays))
    #expect(!OfficeHours.contains(at(monday, 18, 0), start: 9 * 60, end: 18 * 60, days: weekdays))
}

@Test func daysNotOnTheListAreOutsideAllDay() {
    for hour in [0, 9, 12, 17, 23] {
        #expect(!OfficeHours.contains(at(saturday, hour), start: 9 * 60, end: 18 * 60, days: weekdays))
        #expect(!OfficeHours.contains(at(sunday, hour), start: 9 * 60, end: 18 * 60, days: weekdays))
    }
}

@Test func anOvernightWindowCarriesIntoTheNextMorning() {
    let start = 7 * 60          // 07:00 → 00:30 the next day
    let end = 30
    #expect(OfficeHours.contains(at(monday, 7, 0), start: start, end: end, days: weekdays))
    #expect(OfficeHours.contains(at(monday, 23, 59), start: start, end: end, days: weekdays))
    #expect(OfficeHours.contains(at(tuesday, 0, 15), start: start, end: end, days: weekdays))
    #expect(!OfficeHours.contains(at(tuesday, 0, 30), start: start, end: end, days: weekdays))
    #expect(!OfficeHours.contains(at(monday, 6, 59), start: start, end: end, days: weekdays))
}

@Test func anOvernightWindowIsAnchoredToTheDayItStartsOn() {
    let start = 22 * 60         // 22:00 → 02:00
    let end = 2 * 60
    // Friday night's shift spills into Saturday even though Saturday isn't a working day…
    #expect(OfficeHours.contains(at(saturday, 1), start: start, end: end, days: weekdays))
    // …but Saturday night itself never starts one.
    #expect(!OfficeHours.contains(at(saturday, 23), start: start, end: end, days: weekdays))
    #expect(!OfficeHours.contains(at(sunday, 1), start: start, end: end, days: weekdays))
}

@Test func anEmptyDaySetIsNeverInside() {
    #expect(!OfficeHours.contains(at(monday, 12), start: 9 * 60, end: 18 * 60, days: []))
}

@Test func aZeroLengthWindowMeansAWholeRoundTheClockDay() {
    // start == end reads as 24 hours, anchored — like any other window — to the day it starts on:
    // Monday's window runs Mon 09:00 → Tue 09:00.
    #expect(OfficeHours.span(start: 9 * 60, end: 9 * 60) == 24 * 60)
    #expect(OfficeHours.contains(at(monday, 21), start: 9 * 60, end: 9 * 60, days: weekdays))
    #expect(OfficeHours.contains(at(tuesday, 3), start: 9 * 60, end: 9 * 60, days: weekdays))
    // 03:00 on Monday belongs to Sunday's window, and Sunday isn't a working day.
    #expect(!OfficeHours.contains(at(monday, 3), start: 9 * 60, end: 9 * 60, days: weekdays))
    #expect(!OfficeHours.contains(at(sunday, 21), start: 9 * 60, end: 9 * 60, days: weekdays))
}

@Test func spanMeasuresForwardsThroughMidnight() {
    #expect(OfficeHours.span(start: 9 * 60, end: 18 * 60) == 9 * 60)
    #expect(OfficeHours.span(start: 22 * 60, end: 2 * 60) == 4 * 60)
    #expect(OfficeHours.wrap(-30) == 24 * 60 - 30)
    #expect(OfficeHours.previousWeekday(1) == 7)
    #expect(OfficeHours.previousWeekday(6) == 5)
}

@Test func theWindowIsIgnoredEntirelyWhileTheFeatureIsOff() {
    var s = officeSettings()
    s.officeHoursEnabled = false
    #expect(OfficeHours.contains(at(sunday, 3), settings: s))
    s.officeHoursEnabled = true
    #expect(!OfficeHours.contains(at(sunday, 3), settings: s))
}

// MARK: - Engine: pausing outside the window

@Test @MainActor func startingOutsideOfficeHoursComesUpPaused() {
    let h = Harness(officeSettings(), clock: FakeClock(at(monday, 8)))
    h.engine.start()
    #expect(h.engine.phase.pauseReasonsValue == [.outsideOfficeHours])
    #expect(h.engine.isOutsideOfficeHours)
}

@Test @MainActor func offHoursFreezesTheIntervalAndTheFocusClock() {
    let h = Harness(officeSettings(), clock: FakeClock(at(saturday, 11)))
    h.engine.start()
    h.run(120)
    #expect(h.engine.phase.pauseReasonsValue == [.outsideOfficeHours])
    #expect(h.engine.remainingUntilBreak == 100)      // Settings.fast()'s whole interval
    #expect(h.engine.currentSessionFocusTime == 0)
}

@Test @MainActor func officeHoursAreIgnoredWhileTheFeatureIsOff() {
    var s = officeSettings()
    s.officeHoursEnabled = false
    let h = Harness(s, clock: FakeClock(at(sunday, 3)))
    h.engine.start()
    h.run(10)
    #expect(h.engine.phase.isRunning)
    #expect(h.engine.remainingUntilBreak == 90)
}

@Test @MainActor func anOvernightWindowKeepsTheEngineRunningAfterMidnight() {
    var s = officeSettings()
    s.officeHoursStart = 22 * 60
    s.officeHoursEnd = 2 * 60
    let h = Harness(s, clock: FakeClock(at(tuesday, 1)))   // Monday's shift, small hours
    h.engine.start()
    h.run(10)
    #expect(h.engine.phase.isRunning)

    let after = Harness(s, clock: FakeClock(at(tuesday, 3)))
    after.engine.start()
    #expect(after.engine.phase.pauseReasonsValue == [.outsideOfficeHours])
}

// MARK: - Engine: crossing the boundary

@Test @MainActor func leavingOfficeHoursMidRunPausesAndHoldsTheRemainder() {
    let h = Harness(officeSettings(), clock: FakeClock(at(monday, 17, 59)))
    h.engine.start()
    h.run(30)
    #expect(h.engine.remainingUntilBreak == 70)
    h.run(60)                                     // through 18:00
    #expect(h.engine.phase.pauseReasonsValue == [.outsideOfficeHours])
    let held = h.engine.remainingUntilBreak
    #expect(held > 0 && held <= 70)
    h.run(300)
    #expect(h.engine.remainingUntilBreak == held) // still frozen
}

@Test @MainActor func enteringOfficeHoursStartsAFreshInterval() {
    let h = Harness(officeSettings(), clock: FakeClock(at(monday, 17, 59)))
    h.engine.start()
    h.run(30)                                     // burn 30s of the interval
    h.run(60)                                     // 18:00 — off the clock, part-used interval held
    #expect(h.engine.remainingUntilBreak < 100)

    h.jump(15 * 3600)                             // Tuesday 09:00
    #expect(h.engine.phase.isRunning)
    #expect(h.engine.remainingUntilBreak == 100)  // a new working day starts whole
    #expect(h.engine.currentSessionFocusTime == 0)
}

@Test @MainActor func crossingIntoOfficeHoursDoesNotSpendTheOvernightGapOnTheInterval() {
    let h = Harness(officeSettings(), clock: FakeClock(at(monday, 8, 59)))
    h.engine.start()
    h.run(60)                                     // 09:00 — the boundary tick
    #expect(h.engine.phase.isRunning)
    #expect(h.engine.remainingUntilBreak == 100)
    h.run(10)
    #expect(h.engine.remainingUntilBreak == 90)
    #expect(h.events.breakStarts.isEmpty)
}

@Test @MainActor func aBreakAlreadyOnScreenSurvivesTheEndOfTheWorkingDay() {
    var s = officeSettings()
    s.shortBreakDuration = 30
    let h = Harness(s, clock: FakeClock(at(monday, 17, 58).addingTimeInterval(10)))
    h.engine.start()
    h.run(100)                                    // 17:59:50 — the break starts
    #expect(h.engine.phase.isInBreak)
    h.run(20)                                     // 18:00:10 — past the boundary
    #expect(h.engine.phase.isInBreak)
    h.run(15)
    #expect(h.events.breakEndings.contains { $0.1 })          // it ran to completion
    #expect(h.engine.phase.pauseReasonsValue == [.outsideOfficeHours])
}

// MARK: - Engine: settings changes

@Test @MainActor func turningOfficeHoursOnOutsideTheWindowPausesImmediately() {
    var s = officeSettings()
    s.officeHoursEnabled = false
    let h = Harness(s, clock: FakeClock(at(sunday, 3)))
    h.engine.start()
    h.run(10)
    #expect(h.engine.phase.isRunning)

    h.engine.settings.officeHoursEnabled = true
    #expect(h.engine.phase.pauseReasonsValue == [.outsideOfficeHours])

    h.engine.settings.officeHoursStart = 0        // a night shift: 00:00–12:00…
    h.engine.settings.officeHoursEnd = 12 * 60
    #expect(h.engine.phase.pauseReasonsValue == [.outsideOfficeHours])   // …but not on Sundays yet

    h.engine.settings.officeDays = Set(1...7)     // Sunday is a working day after all
    #expect(h.engine.phase.isRunning)
    #expect(h.engine.remainingUntilBreak == 100)  // …and that counts as walking in: fresh interval
}

@Test @MainActor func offHoursCoexistsWithDetectorPausesWithoutLosingEither() {
    let h = Harness(officeSettings(), clock: FakeClock(at(monday, 17, 59)))
    h.engine.start()
    h.engine.updatePauseReasons([.zoomMeeting])
    h.run(120)                                    // through 18:00, still in the call
    #expect(h.engine.phase.pauseReasonsValue == [.zoomMeeting, .outsideOfficeHours])
    h.engine.updatePauseReasons([])               // the call ends; the clock is still off duty
    #expect(h.engine.phase.pauseReasonsValue == [.outsideOfficeHours])
}

@Test @MainActor func stoppingClearsTheOffHoursReason() {
    let h = Harness(officeSettings(), clock: FakeClock(at(saturday, 11)))
    h.engine.start()
    #expect(h.engine.isOutsideOfficeHours)
    h.engine.stop()
    #expect(h.engine.phase.isStopped)
    #expect(!h.engine.isOutsideOfficeHours)
}
