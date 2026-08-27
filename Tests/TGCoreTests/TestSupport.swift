// Shared test scaffolding: a driveable clock, an event recorder, and a few readability helpers.

import Foundation
import Combine
import Testing
@testable import TGCore

// MARK: - Clock

/// A `Clock` the tests move by hand. Every engine deadline is wall-clock based, so advancing this
/// and calling `tick()` is enough to simulate anything — including a laptop lid closed for an hour.
final class FakeClock: Clock, @unchecked Sendable {
    private var current: Date

    /// 10:00 local time on a fixed day, so calendar-rollover tests are unambiguous.
    static var defaultStart: Date {
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_756_000_000))
            .addingTimeInterval(10 * 3600)
    }

    init(_ start: Date = FakeClock.defaultStart) { current = start }

    func now() -> Date { current }

    func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
}

// MARK: - Engine harness

@MainActor
final class Harness {
    let clock: FakeClock
    let engine: BreakEngine
    private(set) var events: [EngineEvent] = []
    private var bag = Set<AnyCancellable>()

    init(_ settings: Settings = Settings(), clock: FakeClock = FakeClock()) {
        self.clock = clock
        self.engine = BreakEngine(settings: settings, clock: clock)
        engine.events.sink { [weak self] event in self?.events.append(event) }.store(in: &bag)
    }

    /// Advance `seconds` of wall clock, delivering a tick every `step` seconds (the app ticks at 1 Hz).
    func run(_ seconds: TimeInterval, step: TimeInterval = 1) {
        var left = seconds
        while left > 0 {
            let chunk = Swift.min(step, left)
            clock.advance(chunk)
            engine.tick()
            left -= chunk
        }
    }

    /// Advance `seconds` with a single tick at the end — a sleep/wake style discontinuity.
    func jump(_ seconds: TimeInterval) {
        clock.advance(seconds)
        engine.tick()
    }

    /// Advance the wall clock without telling the engine (nothing ticks while the Mac is asleep).
    func skipTime(_ seconds: TimeInterval) { clock.advance(seconds) }

    func clearEvents() { events.removeAll() }
}

// MARK: - Settings presets

extension Settings {
    /// Short everything, so a whole break cycle is a handful of ticks.
    static func fast() -> Settings {
        var s = Settings()
        s.shortBreakInterval = 100
        s.shortBreakDuration = 10
        s.longBreakDuration = 20
        s.preBreakWarningSeconds = 10
        s.cursorCountdownSeconds = 5
        s.deferWhileTyping = false
        return s
    }
}

// MARK: - Phase readers

extension EnginePhase {
    var remainingValue: TimeInterval? {
        switch self {
        case .running(_, let r): return r
        case .preBreak(_, let r): return r
        case .paused(_, _, let r): return r
        case .inBreak(_, let r, _): return r
        case .stopped, .waitingForActivityToStop: return nil
        }
    }

    var kindValue: BreakKind? {
        switch self {
        case .running(let k, _): return k
        case .preBreak(let k, _): return k
        case .paused(_, let k, _): return k
        case .inBreak(let k, _, _): return k
        case .waitingForActivityToStop(let k, _): return k
        case .stopped: return nil
        }
    }

    var isRunning: Bool { if case .running = self { return true }; return false }
    var isPreBreak: Bool { if case .preBreak = self { return true }; return false }
    var isStopped: Bool { if case .stopped = self { return true }; return false }
    var isWaitingForActivity: Bool { if case .waitingForActivityToStop = self { return true }; return false }
    var pauseReasonsValue: Set<PauseReason>? { if case .paused(let r, _, _) = self { return r }; return nil }
}

// MARK: - Event readers

extension Array where Element == EngineEvent {
    var preBreakWarnings: [EngineEvent] { filter { if case .preBreakWarning = $0 { return true }; return false } }
    var countdownSeconds: [Int] { compactMap { if case .preBreakCountdown(_, let s) = $0 { return s }; return nil } }
    var breakStarts: [(BreakKind, TimeInterval)] {
        compactMap { if case .breakStarted(let k, let d) = $0 { return (k, d) }; return nil }
    }
    var breakEndings: [(BreakKind, Bool)] {
        compactMap { if case .breakEnded(let k, let c) = $0 { return (k, c) }; return nil }
    }
    var breakTickCount: Int { filter { if case .breakTick = $0 { return true }; return false }.count }
    var snoozes: [(BreakKind, TimeInterval)] {
        compactMap { if case .snoozed(let k, let by) = $0 { return (k, by) }; return nil }
    }
    var skips: [BreakKind] { compactMap { if case .skipped(let k) = $0 { return k }; return nil } }
    var pausedEvents: [Set<PauseReason>] {
        compactMap { if case .paused(let r) = $0 { return r }; return nil }
    }
    var resumedCount: Int { filter { $0 == .resumed }.count }
    var awayDecisions: [(Bool, TimeInterval)] {
        compactMap { if case .awayDecision(let reset, let away) = $0 { return (reset, away) }; return nil }
    }
    var wellnessKinds: [WellnessKind] {
        compactMap { if case .wellnessReminder(let k) = $0 { return k }; return nil }
    }
}

// MARK: - Common pause reasons

extension PauseReason {
    static let zoomMeeting = PauseReason.meeting(appName: "Zoom", bundleID: "us.zoom.xos")
    static let youtubeVideo = PauseReason.video(appName: "Safari", bundleID: "com.apple.Safari")
    static let xcodeFullscreen = PauseReason.fullscreenApp(appName: "Xcode", bundleID: "com.apple.dt.Xcode")
}
