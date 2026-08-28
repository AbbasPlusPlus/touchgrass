// The rest ratio, the stats store's day keying and persistence, and the recorder's screen-time,
// pause-span and break-log accounting (including the midnight split).

import Foundation
import Testing
@testable import TGCore

// MARK: - Harness

@MainActor
final class StatsHarness {
    let clock: FakeClock
    let engine: BreakEngine
    let store: StatsStore
    let recorder: StatsRecorder
    let url: URL

    init(_ settings: Settings = .fast(), clock: FakeClock = FakeClock()) {
        self.clock = clock
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tg-stats-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("stats.json")
        store = StatsStore(settings: settings, url: url)
        engine = BreakEngine(settings: settings, clock: clock)
        recorder = StatsRecorder(engine: engine, store: store, clock: clock)
    }

    func start() {
        engine.start()
        recorder.start()
    }

    /// Advance `seconds` of wall clock, ticking both the engine and the recorder at `step`.
    func run(_ seconds: TimeInterval, step: TimeInterval = 1) {
        var left = seconds
        while left > 0 {
            let chunk = Swift.min(step, left)
            clock.advance(chunk)
            engine.tick()
            recorder.tick()
            left -= chunk
        }
    }

    var today: DayStats { store.stats(for: clock.now()) }
}

// MARK: - Fixtures

@MainActor
private func day(
    sessions: [TimeInterval] = [],
    completed: Int = 0,
    skipped: Int = 0,
    natural: Int = 0,
    snoozes: Int = 0
) -> DayStats {
    var stats = DayStats(dayKey: "2026-01-01")
    var start = Date(timeIntervalSince1970: 1_767_225_600)
    for duration in sessions {
        stats.append(SessionRecord(start: start, duration: duration))
        stats.totalScreenTime += duration
        stats.longestSession = max(stats.longestSession, duration)
        start = start.addingTimeInterval(duration + 60)
    }
    stats.breaksCompleted = completed
    stats.breaksSkipped = skipped
    stats.breaksNatural = natural
    stats.snoozesUsed = snoozes
    return stats
}

private func settings(interval: TimeInterval) -> Settings {
    var s = Settings()
    s.shortBreakInterval = interval
    return s
}

// MARK: - Rest ratio

@Test @MainActor func restRatioIsMinutesRestedPerHourOnScreen() {
    var stats = day(sessions: [3600])
    stats.totalScreenTime = 2 * 3600
    stats.breakTime = 180                       // three minutes of rest over two hours
    let ratio = RestRatio.compute(for: stats, settings: settings(interval: 1200))
    #expect(ratio.minutesPerHour == 1.5)
}

@Test @MainActor func aDayTooShortToDivideHasNoRatio() {
    var stats = day()
    stats.totalScreenTime = 10 * 60             // under the fifteen-minute floor
    stats.breakTime = 60
    #expect(RestRatio.compute(for: stats, settings: settings(interval: 1200)).minutesPerHour == nil)
    #expect(RestRatio.compute(for: stats, settings: settings(interval: 1200)).progress == 0)
}

@Test @MainActor func aNaturalBreakCountsAsOneConfiguredShortBreak() {
    var stats = day(natural: 2)
    stats.totalScreenTime = 3600
    stats.naturalBreakTime = 45 * 60            // a long lunch may not claim a perfect day
    var s = settings(interval: 1200)
    s.shortBreakDuration = 30
    #expect(RestRatio.rest(for: stats, settings: s) == 60)
    #expect(RestRatio.compute(for: stats, settings: s).minutesPerHour == 1)
}

@Test @MainActor func theRestRingFillsToOneAndNoFurther() {
    var stats = day()
    stats.totalScreenTime = 3600
    stats.breakTime = 30
    #expect(RestRatio.compute(for: stats, settings: settings(interval: 1200)).progress == 0.5)

    stats.breakTime = 20 * 60                   // a day of walks is still just a full ring
    let generous = RestRatio.compute(for: stats, settings: settings(interval: 1200))
    #expect(generous.minutesPerHour == 20)
    #expect(generous.progress == 1)
}

// MARK: - Store

@Test @MainActor func dayKeysAreSortableAndZeroPadded() {
    let calendar = Calendar(identifier: .gregorian)
    var components = DateComponents()
    components.year = 2026
    components.month = 3
    components.day = 7
    components.hour = 12
    let date = calendar.date(from: components) ?? Date()
    #expect(StatsStore.dayKey(for: date, calendar: calendar) == "2026-03-07")
}

@Test @MainActor func mutatingADayStampsItsKey() {
    let h = StatsHarness(settings(interval: 1200))
    h.store.mutate(h.clock.now()) { $0.append(SessionRecord(start: h.clock.now(), duration: 2400)) }
    #expect(h.today.dayKey == StatsStore.dayKey(for: h.clock.now()))
    #expect(h.today.hasData == false)   // sessions alone aren't screen time
}

@Test @MainActor func theOldestRecordedDayIsTheOneWithDataInIt() {
    let h = StatsHarness()
    let yesterday = h.clock.now().addingTimeInterval(-24 * 3600)
    h.store.mutate(yesterday) { $0.totalScreenTime = 600 }
    // A day that was touched but never worked in is not somewhere to walk back to.
    h.store.mutate(yesterday.addingTimeInterval(-24 * 3600)) { $0.snoozesUsed = 1 }
    #expect(h.store.oldestRecordedDayKey == StatsStore.dayKey(for: yesterday))
}

@Test @MainActor func statsSurviveAReload() {
    let h = StatsHarness()
    h.start()
    h.run(60)
    h.store.flush()

    let reloaded = StatsStore(settings: .fast(), url: h.url)
    #expect(reloaded.stats(for: h.clock.now()).totalScreenTime == 60)
}

@Test @MainActor func theSessionListIsCapped() {
    var stats = DayStats(dayKey: "2026-01-01")
    let base = Date(timeIntervalSince1970: 0)
    for i in 0...(DayStats.maxSessions + 20) {
        stats.append(SessionRecord(start: base.addingTimeInterval(Double(i)), duration: Double(i + 1)))
    }
    #expect(stats.sessions.count == DayStats.maxSessions)
    // The longest sessions — the ones the timeline is carried by — are the ones that survive.
    #expect(stats.sessions.contains { $0.duration == Double(DayStats.maxSessions + 21) })
    #expect(stats.sessions.contains { $0.duration == 1 } == false)
}

// MARK: - Recorder: screen time

@Test @MainActor func screenTimeAccruesWhileRunning() {
    let h = StatsHarness()
    h.start()
    h.run(50)
    #expect(h.today.totalScreenTime == 50)
    #expect(h.today.longestSession == 50)
    #expect(h.today.hasData)
}

@Test @MainActor func screenTimeFreezesWhilePaused() {
    let h = StatsHarness()
    h.start()
    h.run(10)
    h.engine.updatePauseReasons([.zoomMeeting])
    h.run(30)
    #expect(h.today.totalScreenTime == 10)

    // A meeting doesn't end the session — it just stops the clock on it.
    h.engine.updatePauseReasons([])
    h.run(5)
    #expect(h.today.totalScreenTime == 15)
    #expect(h.today.sessions.count == 1)
    #expect(h.today.sessions.first?.duration == 15)
}

@Test @MainActor func nothingAccruesBeforeStartOrAfterStop() {
    let h = StatsHarness()
    h.run(30)
    #expect(h.today.totalScreenTime == 0)

    h.start()
    h.run(20)
    h.recorder.stop()
    h.run(60)
    #expect(h.today.totalScreenTime == 20)
}

@Test @MainActor func aBreakClosesTheSessionAndANewOneOpensAfter() {
    let h = StatsHarness()   // .fast(): 100 s interval, 10 s short break
    h.start()
    h.run(100)               // the break fires exactly here
    #expect(h.today.sessions.count == 1)
    #expect(h.today.sessions.first?.duration == 100)

    h.run(10)                // break runs to completion
    #expect(h.today.breaksCompleted == 1)
    #expect(h.today.breakTime == 10)

    h.run(20)                // back to work: a fresh session
    #expect(h.today.sessions.count == 2)
    #expect(h.today.sessions.last?.duration == 20)
    #expect(h.today.totalScreenTime == 120)   // the break itself is not screen time
    #expect(h.today.longestSession == 100)
}

@Test @MainActor func aSessionSplitsAtMidnight() {
    var s = Settings()
    s.shortBreakInterval = 100_000   // nothing may interrupt the run
    s.deferWhileTyping = false
    let elevenPM = Calendar.current
        .startOfDay(for: Date(timeIntervalSince1970: 1_756_000_000))
        .addingTimeInterval(23 * 3600)
    let h = StatsHarness(s, clock: FakeClock(elevenPM))
    h.start()
    h.run(2 * 3600, step: 60)

    let firstDay = h.store.stats(for: elevenPM)
    let secondDay = h.store.stats(for: elevenPM.addingTimeInterval(2 * 3600))
    #expect(firstDay.dayKey != secondDay.dayKey)
    #expect(firstDay.totalScreenTime == 3600)
    #expect(secondDay.totalScreenTime == 3600)
    #expect(firstDay.sessions.count == 1)
    #expect(secondDay.sessions.count == 1)
    #expect(firstDay.sessions.first?.duration == 3600)
    #expect(secondDay.sessions.first?.duration == 3600)
    // Neither day inherits the other's total as its longest sit.
    #expect(firstDay.longestSession == 3600)
    #expect(secondDay.longestSession == 3600)
}

// MARK: - Recorder: app usage

@Test @MainActor func appUsageAccruesOnlyWhileScreenTimeDoes() {
    let h = StatsHarness()
    h.start()
    h.recorder.noteFrontmostApp(bundleID: "com.apple.Safari", name: "Safari")
    h.run(40)
    #expect(h.today.appUsage["com.apple.Safari"]?.seconds == 40)
    #expect(h.today.appUsage["com.apple.Safari"]?.name == "Safari")

    // A meeting stops the clock on the app just as it stops it on the day.
    h.engine.updatePauseReasons([.zoomMeeting])
    h.run(30)
    #expect(h.today.appUsage["com.apple.Safari"]?.seconds == 40)

    h.engine.updatePauseReasons([])
    h.run(10)
    #expect(h.today.appUsage["com.apple.Safari"]?.seconds == 50)
    #expect(h.today.totalScreenTime == 50)
}

@Test @MainActor func timeInABreakBelongsToNoApp() {
    let h = StatsHarness()   // .fast(): 100 s interval, 10 s short break
    h.start()
    h.recorder.noteFrontmostApp(bundleID: "com.apple.dt.Xcode", name: "Xcode")
    h.run(100)               // the break fires here
    h.run(10)                // the whole break
    #expect(h.today.appUsage["com.apple.dt.Xcode"]?.seconds == 100)
    #expect(h.today.breaksCompleted == 1)
}

@Test @MainActor func switchingAppsSplitsTheTimeBetweenThem() {
    let h = StatsHarness()
    h.start()
    h.recorder.noteFrontmostApp(bundleID: "com.apple.Safari", name: "Safari")
    h.run(30)
    h.recorder.noteFrontmostApp(bundleID: "com.apple.mail", name: "Mail")
    h.run(20)
    #expect(h.today.appUsage["com.apple.Safari"]?.seconds == 30)
    #expect(h.today.appUsage["com.apple.mail"]?.seconds == 20)
    #expect(h.today.attributedAppTime == h.today.totalScreenTime)

    // Nobody in front: the seconds are still screen time, they just belong to no app.
    h.recorder.noteFrontmostApp(bundleID: nil, name: nil)
    h.run(15)
    #expect(h.today.totalScreenTime == 65)
    #expect(h.today.attributedAppTime == 50)
}

@Test @MainActor func switchingAppsMidTickCreditsTheOutgoingApp() {
    let h = StatsHarness()
    h.start()
    h.recorder.noteFrontmostApp(bundleID: "com.apple.Safari", name: "Safari")
    h.clock.advance(4)
    // No tick yet — the switch itself has to bank Safari's four seconds.
    h.recorder.noteFrontmostApp(bundleID: "com.apple.mail", name: "Mail")
    h.run(6)
    #expect(h.today.appUsage["com.apple.Safari"]?.seconds == 4)
    #expect(h.today.appUsage["com.apple.mail"]?.seconds == 6)
}

@Test @MainActor func appUsageSplitsAtMidnight() {
    var s = Settings()
    s.shortBreakInterval = 100_000   // nothing may interrupt the run
    s.deferWhileTyping = false
    let elevenPM = Calendar.current
        .startOfDay(for: Date(timeIntervalSince1970: 1_756_000_000))
        .addingTimeInterval(23 * 3600)
    let h = StatsHarness(s, clock: FakeClock(elevenPM))
    h.start()
    h.recorder.noteFrontmostApp(bundleID: "com.apple.Safari", name: "Safari")
    h.run(2 * 3600, step: 60)

    let firstDay = h.store.stats(for: elevenPM)
    let secondDay = h.store.stats(for: elevenPM.addingTimeInterval(2 * 3600))
    #expect(firstDay.appUsage["com.apple.Safari"]?.seconds == 3600)
    #expect(secondDay.appUsage["com.apple.Safari"]?.seconds == 3600)
}

@Test @MainActor func appUsageIsNotRecordedWhenTheUserTurnsItOff() {
    var s = Settings.fast()
    s.trackAppUsage = false
    let h = StatsHarness(s)
    h.start()
    h.recorder.noteFrontmostApp(bundleID: "com.apple.Safari", name: "Safari")
    h.run(40)
    #expect(h.today.totalScreenTime == 40)
    #expect(h.today.appUsage.isEmpty)
}

// MARK: - App usage: the map itself

@Test @MainActor func theAppMapIsCappedAndDropsTheSmallest() {
    var stats = DayStats(dayKey: "2026-01-01")
    for i in 0...(DayStats.maxTrackedApps + 20) {
        stats.addAppUsage(bundleID: "app.\(i)", name: "App \(i)", seconds: TimeInterval(i + 1))
    }
    #expect(stats.appUsage.count == DayStats.maxTrackedApps)
    // The longest-used apps — the only ones the card ever draws — are the survivors.
    #expect(stats.appUsage["app.\(DayStats.maxTrackedApps + 20)"] != nil)
    #expect(stats.appUsage["app.0"] == nil)
}

@Test @MainActor func appUsageIsRankedLongestFirst() {
    var stats = DayStats(dayKey: "2026-01-01")
    stats.addAppUsage(bundleID: "com.apple.mail", name: "Mail", seconds: 60)
    stats.addAppUsage(bundleID: "com.apple.Safari", name: "Safari", seconds: 120)
    stats.addAppUsage(bundleID: "com.apple.Safari", name: "Safari", seconds: 30)
    let ranked = stats.rankedAppUsage()
    #expect(ranked.map(\.name) == ["Safari", "Mail"])
    #expect(ranked.first?.seconds == 150)
    #expect(stats.rankedAppUsage(limit: 1).count == 1)
    #expect(stats.attributedAppTime == 210)
}

@Test @MainActor func aDayWrittenBeforeAppTrackingStillDecodes() {
    // Exactly what an older build wrote: no `appUsage` key at all, and one counter this build
    // has since retired — neither may cost the user their history.
    let json = #"{"version":1,"days":{"2026-01-01":{"dayKey":"2026-01-01","#
        + #""totalScreenTime":1200,"longestSession":1200,"sessions":[],"breaksCompleted":2,"#
        + #""breakTime":90,"breaksSkipped":1,"breaksNatural":0,"naturalBreakTime":0,"#
        + #""snoozesUsed":0,"retiredCounter":88}}}"#
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tg-stats-legacy-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("stats.json")
    try? Data(json.utf8).write(to: url)

    let store = StatsStore(settings: .fast(), url: url)
    let day = store.days["2026-01-01"]
    #expect(day?.totalScreenTime == 1200)
    #expect(day?.breaksCompleted == 2)
    #expect(day?.appUsage.isEmpty == true)
}

// MARK: - Recorder: breaks

@Test @MainActor func skipsAreCountedOnceEvenThoughTheEngineAlsoEndsTheBreak() {
    var s = Settings.fast()
    s.enforcement = .casual
    let h = StatsHarness(s)
    h.start()
    h.run(100)               // break on screen
    h.engine.skipBreak()
    #expect(h.today.breaksSkipped == 1)
    #expect(h.today.breaksCompleted == 0)
}

@Test @MainActor func snoozesAreCountedAndNotMistakenForSkips() {
    let h = StatsHarness()
    h.start()
    h.run(95)                // pre-break
    h.engine.snooze(60)
    #expect(h.today.snoozesUsed == 1)
    #expect(h.today.breaksSkipped == 0)
    #expect(h.today.breaksCompleted == 0)
}

@Test @MainActor func walkingAwayLongEnoughIsRecordedAsANaturalBreak() {
    var s = Settings.fast()
    s.idlePauseAfter = 20
    s.idleResetAfter = 60
    let h = StatsHarness(s)
    h.start()
    h.run(30)
    h.engine.updateIdleSeconds(25)   // away since t = 5
    h.run(70)
    h.engine.updateIdleSeconds(0)    // back at t = 100, away for 95 s

    #expect(h.today.breaksNatural == 1)
    #expect(h.today.naturalBreakTime == 95)
    #expect(h.today.breaksCompleted == 0)
    // The away decision closes the session it interrupted.
    #expect(h.today.sessions.count == 1)
    #expect(h.today.sessions.first?.duration == 30)
}

@Test @MainActor func endingABreakEarlyRecordsTheTimeActuallyRested() {
    var s = Settings.fast()
    s.shortBreakDuration = 100
    s.allowEndBreakEarlyAfterFraction = 0.5
    let h = StatsHarness(s)
    h.start()
    h.run(100)               // break starts
    h.run(60)                // 60 s of a 100 s break
    h.engine.endBreakEarly()
    #expect(h.today.breaksCompleted == 1)
    #expect(h.today.breakTime == 60)
}

// MARK: - Recorder: pause spans

@Test @MainActor func aPauseIsRecordedAsASpanOfTheDay() {
    let h = StatsHarness()
    h.start()
    h.run(10)
    h.engine.updatePauseReasons([.zoomMeeting])
    h.run(30)
    h.engine.updatePauseReasons([])
    h.run(5)

    #expect(h.today.pauses.count == 1)
    #expect(h.today.pauses.first?.duration == 30)
    #expect(h.today.pauses.first?.kind == .meeting)
    // The pause is not screen time, and it didn't end the session either.
    #expect(h.today.totalScreenTime == 15)
    #expect(h.today.sessions.count == 1)
}

@Test @MainActor func aChangeOfReasonClosesOneSpanAndOpensAnother() {
    let h = StatsHarness()
    h.start()
    h.engine.updatePauseReasons([.zoomMeeting])
    h.run(20)
    h.engine.updatePauseReasons([.xcodeFullscreen])
    h.run(10)
    h.engine.updatePauseReasons([])

    #expect(h.today.pauses.map(\.kind) == [.meeting, .fullscreen])
    #expect(h.today.pauses.map(\.duration) == [20, 10])
}

@Test @MainActor func anOpenPauseIsBankedWhenTheRecorderStops() {
    let h = StatsHarness()
    h.start()
    h.engine.updatePauseReasons([.youtubeVideo])
    h.run(45)
    h.recorder.stop()

    #expect(h.today.pauses.count == 1)
    #expect(h.today.pauses.first?.duration == 45)
    #expect(h.today.pauses.first?.kind == .video)
}

@Test @MainActor func aPauseSplitsAtMidnight() {
    var s = Settings()
    s.shortBreakInterval = 100_000   // nothing may interrupt the run
    s.deferWhileTyping = false
    let elevenPM = Calendar.current
        .startOfDay(for: Date(timeIntervalSince1970: 1_756_000_000))
        .addingTimeInterval(23 * 3600)
    let h = StatsHarness(s, clock: FakeClock(elevenPM))
    h.start()
    h.engine.updatePauseReasons([.zoomMeeting])
    h.run(2 * 3600, step: 60)
    h.engine.updatePauseReasons([])

    let firstDay = h.store.stats(for: elevenPM)
    let secondDay = h.store.stats(for: elevenPM.addingTimeInterval(2 * 3600))
    #expect(firstDay.pauses.count == 1)
    #expect(secondDay.pauses.count == 1)
    #expect(firstDay.pauses.first?.duration == 3600)
    #expect(secondDay.pauses.first?.duration == 3600)
    #expect(secondDay.pauses.first?.start == Calendar.current.startOfDay(for: secondDay.pauses[0].start))
}

@Test @MainActor func theHighestPriorityReasonNamesTheSpan() {
    #expect(PauseKind.primary(of: [.zoomMeeting, .xcodeFullscreen]) == .meeting)
    #expect(PauseKind.primary(of: [.xcodeFullscreen, .idle]) == .fullscreen)
    #expect(PauseKind.primary(of: [.screenLocked]) == .other)
    #expect(PauseKind.primary(of: []) == nil)
}

// MARK: - Recorder: the break log

@Test @MainActor func aCompletedBreakIsLoggedWhereItHappened() {
    let h = StatsHarness()   // .fast(): 100 s interval, 10 s short break
    let start = h.clock.now()
    h.start()
    h.run(100)               // the break fires exactly here
    h.run(10)                // and runs to completion

    #expect(h.today.breaks.count == 1)
    #expect(h.today.breaks.first?.outcome == .completed)
    #expect(h.today.breaks.first?.kind == .short)
    #expect(h.today.breaks.first?.at == start.addingTimeInterval(100))
}

@Test @MainActor func aSkippedBreakIsLoggedAsSkipped() {
    var s = Settings.fast()
    s.enforcement = .casual          // balanced would still be counting out its skip delay
    let h = StatsHarness(s)
    h.start()
    h.run(100)               // the break is on screen
    h.engine.skipBreak()

    #expect(h.today.breaksSkipped == 1)
    #expect(h.today.breaks.map(\.outcome) == [.skipped])
}

@Test @MainActor func anAwayResetIsLoggedAsANaturalBreak() {
    var s = Settings.fast()
    s.shortBreakInterval = 100_000   // the away decision is the only thing that may fire
    let h = StatsHarness(s)
    h.start()
    h.run(120)
    h.engine.updateIdleSeconds(120)
    h.clock.advance(400)             // total away 520 s, past idleResetAfter
    h.engine.updateIdleSeconds(0)

    #expect(h.today.breaksNatural == 1)
    #expect(h.today.breaks.map(\.outcome) == [.natural])
    #expect(h.today.breaks.first?.kind == .short)
}

// MARK: - The capped arrays

@Test @MainActor func thePauseListIsCappedAndDropsTheShortest() {
    var stats = DayStats(dayKey: "2026-01-01")
    let base = Date(timeIntervalSince1970: 0)
    for i in 0...(DayStats.maxPauses + 10) {
        stats.appendPause(IntervalRecord(start: base.addingTimeInterval(Double(i)),
                                         duration: Double(i + 1),
                                         kind: .meeting))
    }
    #expect(stats.pauses.count == DayStats.maxPauses)
    #expect(stats.pauses.contains { $0.duration == Double(DayStats.maxPauses + 11) })
    #expect(stats.pauses.contains { $0.duration == 1 } == false)
    // A zero-length span is a detector flicker, not a fact about the day.
    stats.appendPause(IntervalRecord(start: base, duration: 0, kind: .idle))
    #expect(stats.pauses.count == DayStats.maxPauses)
}

@Test @MainActor func theBreakListIsCappedAndDropsTheOldest() {
    var stats = DayStats(dayKey: "2026-01-01")
    let base = Date(timeIntervalSince1970: 0)
    for i in 0...(DayStats.maxBreaks + 5) {
        stats.appendBreak(BreakRecord(at: base.addingTimeInterval(Double(i)),
                                      kind: .short,
                                      outcome: i.isMultiple(of: 2) ? .completed : .skipped))
    }
    #expect(stats.breaks.count == DayStats.maxBreaks)
    #expect(stats.breaks.first?.at == base.addingTimeInterval(6))
    #expect(stats.restBreaks.count + stats.skippedBreaks.count == DayStats.maxBreaks)
}

@Test @MainActor func aRecordWrittenByAnOlderBuildStillDecodes() throws {
    // No `pauses` and no `breaks` keys, plus a counter this build no longer knows: exactly what
    // a 1.0.2 stats.json looks like from here.
    let json = Data("""
    {"dayKey":"2026-01-01","totalScreenTime":600,"breaksCompleted":2,"retiredCounter":62}
    """.utf8)
    let decoded = try JSONDecoder().decode(DayStats.self, from: json)
    #expect(decoded.totalScreenTime == 600)
    #expect(decoded.breaksCompleted == 2)
    #expect(decoded.pauses.isEmpty)
    #expect(decoded.breaks.isEmpty)
}
