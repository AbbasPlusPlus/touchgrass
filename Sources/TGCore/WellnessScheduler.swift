// TGCore — WellnessScheduler: blink and posture nudges.
//
// This is the app's *second* clock and it deliberately behaves differently from BreakEngine:
//   * Break timing measures **screen time** — it freezes whenever Smart Pause kicks in.
//   * Wellness timing measures **real time** — a meeting or a video doesn't stop you from blinking,
//     so the nudges keep coming. The one exception is a break that's actually on screen: a nudge on
//     top of a break overlay is noise, so the counters hold while `isInBreak` is true.
// ( users routinely trip over this difference; the split is intentional.)

import Foundation
import Combine

@MainActor
public final class WellnessScheduler: ObservableObject {

    @Published public private(set) var isRunning = false
    /// Real-time seconds until the next blink / posture nudge. `nil` when that reminder is off.
    @Published public private(set) var nextBlinkIn: TimeInterval?
    @Published public private(set) var nextPostureIn: TimeInterval?

    public let events = PassthroughSubject<EngineEvent, Never>()

    public var settings: Settings {
        didSet { settingsDidChange(from: oldValue) }
    }

    private let clock: Clock
    private var lastTickAt: Date?
    private var blinkRemaining: TimeInterval
    private var postureRemaining: TimeInterval

    public init(settings: Settings, clock: Clock = SystemClock()) {
        self.settings = settings
        self.clock = clock
        self.blinkRemaining = settings.blinkReminderInterval
        self.postureRemaining = settings.postureReminderInterval
    }

    // MARK: - Lifecycle

    public func start() {
        isRunning = true
        lastTickAt = clock.now()
        resetAll()
    }

    public func stop() {
        isRunning = false
        lastTickAt = nil
        resetAll()
    }

    /// Put both counters back to a full interval. Called by the app after a break ends so a nudge
    /// doesn't land seconds after the user just rested.
    public func resetAfterBreak() {
        resetAll()
    }

    // MARK: - Tick

    /// Advance on wall-clock time. `isInBreak` freezes the counters (and suppresses nudges) while a
    /// break overlay is up; every other kind of pause is ignored on purpose.
    public func tick(isInBreak: Bool) {
        let now = clock.now()
        let dt = max(0, now.timeIntervalSince(lastTickAt ?? now))
        lastTickAt = now

        guard isRunning, dt > 0 else { publish(); return }
        guard !isInBreak else { publish(); return }

        if settings.blinkRemindersEnabled, settings.blinkReminderInterval > 0 {
            blinkRemaining -= dt
            if blinkRemaining <= 0 {
                blinkRemaining = settings.blinkReminderInterval
                events.send(.wellnessReminder(.blink))
            }
        }
        if settings.postureRemindersEnabled, settings.postureReminderInterval > 0 {
            postureRemaining -= dt
            if postureRemaining <= 0 {
                postureRemaining = settings.postureReminderInterval
                events.send(.wellnessReminder(.posture))
            }
        }
        publish()
    }

    // MARK: - Internals

    private func resetAll() {
        blinkRemaining = settings.blinkReminderInterval
        postureRemaining = settings.postureReminderInterval
        publish()
    }

    private func publish() {
        let blink = isRunning && settings.blinkRemindersEnabled ? max(0, blinkRemaining) : nil
        let posture = isRunning && settings.postureRemindersEnabled ? max(0, postureRemaining) : nil
        if blink != nextBlinkIn { nextBlinkIn = blink }
        if posture != nextPostureIn { nextPostureIn = posture }
    }

    private func settingsDidChange(from old: Settings) {
        guard old != settings else { return }

        if !old.blinkRemindersEnabled && settings.blinkRemindersEnabled {
            blinkRemaining = settings.blinkReminderInterval
        } else if old.blinkReminderInterval != settings.blinkReminderInterval {
            // Shift the deadline by the delta rather than restarting it, then clamp to the new interval.
            blinkRemaining = min(max(0, blinkRemaining + settings.blinkReminderInterval - old.blinkReminderInterval),
                                 settings.blinkReminderInterval)
        }

        if !old.postureRemindersEnabled && settings.postureRemindersEnabled {
            postureRemaining = settings.postureReminderInterval
        } else if old.postureReminderInterval != settings.postureReminderInterval {
            postureRemaining = min(max(0, postureRemaining + settings.postureReminderInterval - old.postureReminderInterval),
                                   settings.postureReminderInterval)
        }
        publish()
    }
}
