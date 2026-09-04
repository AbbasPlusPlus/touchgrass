// TGOverlay — everything the break screen needs to draw itself, and the three things it can do.
// The engine owns time; this object only mirrors it. It never computes a deadline.

import AppKit
import Combine
import SwiftUI
import TGCore

@MainActor
public final class BreakViewModel: ObservableObject {

    // MARK: - Content

    @Published public private(set) var kind: BreakKind = .short
    @Published public private(set) var title: String = "Relax those eyes"
    @Published public private(set) var subtitle: String? = "Find a distant spot to rest your eyes on"
    @Published public private(set) var remaining: TimeInterval = 0
    @Published public private(set) var total: TimeInterval = 1

    /// Wall-clock instant the countdown reaches zero. Re-synced from the engine on every tick, but
    /// stable enough between ticks that a display-rate `TimelineView` can read it for a countdown
    /// that steps down evenly — instead of aliasing the fractional `remaining` against ~1 Hz ticks
    /// (which made a number stick for two seconds, then jump one).
    @Published public private(set) var deadline: Date = .distantPast

    // MARK: - Rules

    @Published public private(set) var enforcement: Enforcement = .balanced
    @Published public private(set) var skipUnlocked: Bool = true
    @Published public private(set) var skipDelay: TimeInterval = 0
    @Published public private(set) var snoozesRemaining: Int = 0
    @Published public private(set) var canEndEarly: Bool = false

    // MARK: - Appearance (copied from Settings at break start)

    @Published public private(set) var background: BreakBackground = .wallpaper
    @Published public private(set) var showTitle: Bool = true
    @Published public private(set) var showSubtitle: Bool = true
    @Published public private(set) var showClock: Bool = true
    @Published public private(set) var showCountdownOnAllDisplays: Bool = false

    // MARK: - Actions

    public var onSkip: () -> Void = {}
    public var onSnooze: (TimeInterval) -> Void = { _ in }
    public var onEndEarly: () -> Void = {}
    public var onLockScreen: () -> Void = {}

    // MARK: - Derived

    public var progress: Double { total > 0 ? min(1, max(0, 1 - remaining / total)) : 0 }

    public var showsSkip: Bool { enforcement != .hardcore && !canEndEarly }
    public var skipEnabled: Bool { enforcement == .casual || skipUnlocked }
    public var showsSnoozes: Bool { snoozesRemaining > 0 }

    /// mm:ss remaining as of `now`, read from `deadline` so a display-rate timer can call it many
    /// times a second and get an even, non-juddering countdown.
    public func countdownText(asOf now: Date = Date()) -> String {
        let clamped = max(0, deadline.timeIntervalSince(now).rounded(.up))
        let minutes = Int(clamped) / 60
        let seconds = Int(clamped) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public var snoozeCaption: String? {
        guard snoozesRemaining > 0 else { return nil }
        return snoozesRemaining == 1 ? "1 snooze left" : "\(snoozesRemaining) snoozes left"
    }

    /// What double-Escape does right now, for the keycap hint. Nil when Esc does nothing.
    public var escHintAction: String? {
        if settings.doubleEscapeSkips {
            guard enforcement != .hardcore else { return nil }
            return "skip the break"
        }
        guard snoozesRemaining > 0 else { return nil }
        return "snooze the break"
    }

    // MARK: - Private state

    private var settings = TGCore.Settings()
    private var escapeMonitor: Any?
    private var lastEscape: Date?
    private var unlockTask: Task<Void, Never>?

    public init() {}

    deinit {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
    }

    // MARK: - Lifecycle

    /// Called once when a break begins. Picks the message, snapshots the rules, arms the Esc monitor.
    public func beginBreak(kind: BreakKind,
                           total: TimeInterval,
                           settings: TGCore.Settings,
                           snoozesRemaining: Int) {
        self.settings = settings
        self.kind = kind
        self.total = max(total, 1)
        self.remaining = total
        self.deadline = Date().addingTimeInterval(max(0, total))
        self.enforcement = settings.enforcement
        self.snoozesRemaining = max(0, snoozesRemaining)
        self.canEndEarly = false

        self.background = settings.background
        self.showTitle = settings.showTitle
        self.showSubtitle = settings.showSubtitle
        self.showClock = settings.showClock
        self.showCountdownOnAllDisplays = settings.showCountdownOnAllDisplays

        let message = Self.randomMessage(for: kind, settings: settings)
        self.title = message.title
        self.subtitle = message.subtitle

        self.skipDelay = settings.enforcement == .balanced ? settings.balancedSkipDelaySeconds : 0
        self.skipUnlocked = settings.enforcement == .casual
        armSkipUnlock()
        startEscapeMonitor()
    }

    /// Called on every engine tick.
    public func update(remaining: TimeInterval, snoozesRemaining: Int) {
        self.remaining = max(0, remaining)
        self.deadline = Date().addingTimeInterval(self.remaining)
        self.snoozesRemaining = max(0, snoozesRemaining)
        let elapsedFraction = total > 0 ? (total - self.remaining) / total : 0
        // "End break early" is a long-break courtesy: short breaks are over before it would matter.
        self.canEndEarly = kind == .long
            && elapsedFraction >= settings.allowEndBreakEarlyAfterFraction
            && enforcement != .hardcore
    }

    public func endBreak() {
        unlockTask?.cancel()
        unlockTask = nil
        stopEscapeMonitor()
    }

    // MARK: - Messages

    public static func randomMessage(for kind: BreakKind,
                                     settings: TGCore.Settings) -> (title: String, subtitle: String?) {
        let pool = kind == .short ? settings.shortBreakMessages : settings.longBreakMessages
        guard let raw = pool.randomElement(), !raw.isEmpty else {
            return kind == .short
                ? ("Relax those eyes", "Find a distant spot to rest your eyes on")
                : ("Step away", "Stretch, get some water, look out a window")
        }
        return TGCore.Settings.splitMessage(raw)
    }

    // MARK: - Balanced skip delay

    private func armSkipUnlock() {
        unlockTask?.cancel()
        guard enforcement == .balanced, skipDelay > 0 else { return }
        let delay = skipDelay
        unlockTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.skipUnlocked = true
        }
    }

    // MARK: - Double Escape

    /// Two Escapes within 600 ms skip (or snooze 5 min, per `doubleEscapeSkips`).
    /// A local monitor is enough because the break panel takes key as a `.nonactivatingPanel`.
    private func startEscapeMonitor() {
        stopEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }   // 53 = Escape
            MainActor.assumeIsolated { self.handleEscape() }
            return nil                                                   // swallow it
        }
    }

    private func stopEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        lastEscape = nil
    }

    private func handleEscape() {
        let now = Date()
        guard let previous = lastEscape, now.timeIntervalSince(previous) <= 0.6 else {
            lastEscape = now
            return
        }
        lastEscape = nil

        if settings.doubleEscapeSkips {
            guard enforcement != .hardcore, skipEnabled else { return }
            onSkip()
        } else {
            guard snoozesRemaining > 0 else { return }
            onSnooze(5 * 60)
        }
    }
}
