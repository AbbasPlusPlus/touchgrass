// TGCore — WellnessScheduler: blink and posture nudges.
//
// This is the app's *second* clock and it deliberately behaves differently from BreakEngine:
//   * Break timing measures **screen time** — it freezes whenever Smart Pause kicks in.
//   * Wellness timing measures **real time** — a meeting or a video doesn't stop you from blinking,
//     so the nudges keep coming. The one exception is a break that's actually on screen: a nudge on
//     top of a break overlay is noise, so the counters hold while `isInBreak` is true.
// (users of similar apps routinely trip over this difference; the split is intentional.)
//
// Custom reminders (water / stretch / eye drops, `Settings.customReminders`) run on exactly the
// same real-time cadence as blink and posture, freeze during a break the same way, and are reset
// by `resetAfterBreak()` the same way.

import Foundation
import Combine

@MainActor
public final class WellnessScheduler: ObservableObject {

    @Published public private(set) var isRunning = false
    /// Real-time seconds until the next blink / posture nudge. `nil` when that reminder is off.
    @Published public private(set) var nextBlinkIn: TimeInterval?
    @Published public private(set) var nextPostureIn: TimeInterval?
    /// Real-time seconds until the soonest enabled custom reminder. `nil` when none is scheduled.
    @Published public private(set) var nextCustomIn: TimeInterval?

    public let events = PassthroughSubject<EngineEvent, Never>()

    public var settings: Settings {
        didSet { settingsDidChange(from: oldValue) }
    }

    private let clock: Clock
    private var lastTickAt: Date?
    private var blinkRemaining: TimeInterval
    private var postureRemaining: TimeInterval
    /// Seconds left per custom reminder, keyed by `CustomReminder.id`.
    private var customRemaining: [UUID: TimeInterval] = [:]

    public init(settings: Settings, clock: Clock = SystemClock()) {
        self.settings = settings
        self.clock = clock
        self.blinkRemaining = settings.blinkReminderInterval
        self.postureRemaining = settings.postureReminderInterval
        self.customRemaining = Self.freshCustomRemaining(settings.customReminders)
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
        advanceCustomReminders(dt: dt)
        publish()
    }

    // MARK: - Internals

    private func resetAll() {
        blinkRemaining = settings.blinkReminderInterval
        postureRemaining = settings.postureReminderInterval
        customRemaining = Self.freshCustomRemaining(settings.customReminders)
        publish()
    }

    /// One interval per reminder, ids preserved. Duplicated ids (hand-edited JSON) collapse — the
    /// dictionary is the source of truth and a reminder without an entry starts from a full interval.
    private static func freshCustomRemaining(_ reminders: [CustomReminder]) -> [UUID: TimeInterval] {
        var result: [UUID: TimeInterval] = [:]
        for reminder in reminders { result[reminder.id] = reminder.interval }
        return result
    }

    /// Same shape as blink/posture: count down, fire once, re-arm. A single tick never fires the
    /// same reminder twice, however large the wall-clock jump.
    private func advanceCustomReminders(dt: TimeInterval) {
        guard !settings.customReminders.isEmpty else { return }
        for reminder in settings.customReminders where reminder.isSchedulable {
            var left = (customRemaining[reminder.id] ?? reminder.interval) - dt
            if left <= 0 {
                left = reminder.interval
                events.send(.customReminder(title: reminder.displayTitle, symbol: reminder.displaySymbol))
            }
            customRemaining[reminder.id] = left
        }
    }

    private func publish() {
        let blink = isRunning && settings.blinkRemindersEnabled ? max(0, blinkRemaining) : nil
        let posture = isRunning && settings.postureRemindersEnabled ? max(0, postureRemaining) : nil
        if blink != nextBlinkIn { nextBlinkIn = blink }
        if posture != nextPostureIn { nextPostureIn = posture }

        let custom = isRunning
            ? settings.customReminders
                .filter(\.isSchedulable)
                .map { Swift.max(0, customRemaining[$0.id] ?? $0.interval) }
                .min()
            : nil
        if custom != nextCustomIn { nextCustomIn = custom }
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

        syncCustomReminders(from: old.customReminders)
        publish()
    }

    /// Adds, removes and re-times custom reminders without disturbing the ones that didn't change.
    /// A brand-new or newly-enabled reminder starts from a full interval; an edited interval shifts
    /// the deadline by the delta (clamped), exactly like blink and posture.
    private func syncCustomReminders(from old: [CustomReminder]) {
        guard old != settings.customReminders else { return }
        let previous = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var updated: [UUID: TimeInterval] = [:]
        for reminder in settings.customReminders {
            guard let before = previous[reminder.id] else {
                updated[reminder.id] = reminder.interval          // added
                continue
            }
            let left = customRemaining[reminder.id] ?? before.interval
            if !before.enabled && reminder.enabled {
                updated[reminder.id] = reminder.interval          // switched on
            } else if before.interval != reminder.interval {
                updated[reminder.id] = min(max(0, left + reminder.interval - before.interval),
                                           reminder.interval)
            } else {
                updated[reminder.id] = left
            }
        }
        customRemaining = updated                                 // removals fall out here
    }
}
