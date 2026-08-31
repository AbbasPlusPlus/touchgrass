// TGOverlay — the one object the app wires up. It listens to the engine and decides which
// surface should exist right now. It never computes timing and never calls back into the engine
// except from an explicit user action.

import AppKit
import Combine
import SwiftUI
import TGAudio
import TGCore

@MainActor
public final class OverlayCoordinator {

    // MARK: - Surfaces

    private let overlay = BreakOverlayController()
    private let card = PreBreakCard()
    private let pill = CursorPill()
    private let toast = ToastPanel()
    private let wellness = WellnessNudgeController()
    private let sound = SoundPlayer()

    // MARK: - Dependencies

    private let engine: BreakEngine
    private let settingsStore: SettingsStore
    private var cancellables = Set<AnyCancellable>()
    private var lastPhase: EnginePhase = .stopped

    private var settings: TGCore.Settings { settingsStore.settings }

    public init(engine: BreakEngine, settingsStore: SettingsStore) {
        self.engine = engine
        self.settingsStore = settingsStore

        sound.customSoundURL = settingsStore.settings.customSoundURL
        settingsStore.$settings
            .map(\.customSoundURL)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] url in self?.sound.customSoundURL = url }
            .store(in: &cancellables)

        wireUserActions()

        engine.events
            .receive(on: RunLoop.main)
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)

        engine.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in self?.handle(phase: phase) }
            .store(in: &cancellables)
    }

    // MARK: - User actions → engine

    private func wireUserActions() {
        overlay.model.onSkip = { [weak self] in self?.engine.skipBreak() }
        overlay.model.onSnooze = { [weak self] seconds in self?.engine.snooze(seconds) }
        overlay.model.onEndEarly = { [weak self] in self?.engine.endBreakEarly() }
        overlay.model.onLockScreen = { Self.lockScreenNow() }
        installLockObservers()

        card.onStart = { [weak self] in
            guard let self else { return }
            // A user action, like the others — never fired automatically.
            self.engine.startBreakNow(self.pendingKind)
        }
        card.onSnooze = { [weak self] seconds in self?.engine.snooze(seconds) }
    }

    private var pendingKind: BreakKind = .short

    // MARK: - Events

    private func handle(_ event: EngineEvent) {
        switch event {

        case .preBreakWarning(let kind, let startsIn):
            pendingKind = kind
            if settings.preBreakEnabled {
                card.style = .notch
                card.show(kind: kind,
                          secondsLeft: Int(startsIn.rounded()),
                          snoozesRemaining: snoozesRemaining,
                          visibleSeconds: settings.preBreakCardVisibleSeconds,
                          breakDuration: kind == .long ? settings.longBreakDuration
                                                       : settings.shortBreakDuration)
            }
            if settings.soundOnPreBreak {
                sound.play(settings.soundStyle, event: .preBreak, volume: settings.volume)
            }

        case .preBreakCountdown(let kind, let secondsLeft):
            pendingKind = kind
            card.update(secondsLeft: secondsLeft, snoozesRemaining: snoozesRemaining)
            let label = kind == .long
                ? "Starting long break in \(max(0, secondsLeft))"
                : "Starting break in \(max(0, secondsLeft))"
            if pill.isShowing {
                pill.update(symbol: Self.symbol(for: kind), text: label)
            } else {
                pill.show(symbol: Self.symbol(for: kind), text: label)
            }

        case .breakStarted(let kind, let duration):
            card.hide()
            pill.hide()
            wellness.hide()
            overlay.model.beginBreak(kind: kind,
                                     total: duration,
                                     settings: settings,
                                     snoozesRemaining: snoozesRemaining)
            overlay.show()
            if settings.soundOnBreakStart {
                sound.play(settings.soundStyle, event: .breakStart, volume: settings.volume)
            }
            if settings.lockScreenOnBreakStart { scheduleScreenLock() }

        case .breakTick(_, let remaining):
            overlay.model.update(remaining: remaining, snoozesRemaining: snoozesRemaining)

        case .breakEnded(_, let completed):
            overlay.hide()
            if completed && settings.soundOnBreakEnd {
                sound.play(settings.soundStyle, event: .breakEnd, volume: settings.volume)
            }

        case .snoozed(_, let by):
            card.hide()
            pill.hide()
            overlay.hide()
            toast.show(symbol: "zzz", text: "Snoozed \(Self.minutesLabel(by))")

        case .skipped:
            card.hide()
            pill.hide()
            overlay.hide()

        case .paused:
            // No toast, ever. A pause reason carries the frontmost app's name, so every window
            // switch inside a call produced a *different* reason, a set change, and another
            // "Call detected on Zoom" banner. The menu bar already says "Paused · Meeting" and
            // that is the whole indicator; the only toasts left in the app are the two that
            // offer an action or confirm one (the away-decision Undo, and "Snoozed 5 minutes").
            card.hide()
            pill.hide()

        case .resumed:
            break

        case .awayDecision(let resetTimer, let awayFor):
            // After a long absence (lunch, overnight) the reset is self-evident and nobody wants
            // to undo it — greeting them with a toast is noise. The toast only exists for the
            // debatable case: an away just over the reset threshold, where "Undo" earns its place.
            guard awayFor < Self.awayToastCutoff else { break }
            let text = resetTimer
                ? "Timer reset — you were away \(Self.minutesLabel(awayFor))"
                : "Welcome back — picking up where you left off"
            toast.show(symbol: "clock.arrow.circlepath",
                       text: text,
                       undoTitle: "Undo",
                       undo: { [weak self] in self?.engine.undoAwayDecision() })

        case .wellnessReminder(let kind):
            guard !overlay.isShowing else { break }
            wellness.show(kind,
                          dimsScreen: settings.wellnessDimsScreen,
                          mainScreenOnly: settings.wellnessMainScreenOnly)

        case .customReminder(let title, let symbol):
            guard !overlay.isShowing else { break }
            wellness.showCustom(title: title,
                                symbol: symbol,
                                dimsScreen: settings.wellnessDimsScreen,
                                mainScreenOnly: settings.wellnessMainScreenOnly)
        }
    }

    // MARK: - Phase

    private func handle(phase: EnginePhase) {
        defer { lastPhase = phase }

        switch phase {
        case .waitingForActivityToStop(_, let hint):
            let symbol = Self.symbol(for: hint)
            if pill.isShowing {
                pill.update(symbol: symbol, text: hint.label)
            } else {
                pill.show(symbol: symbol, text: hint.label)
            }

        case .running, .stopped:
            pill.hide()
            card.hide()

        case .preBreak, .inBreak, .paused:
            break
        }
    }

    // MARK: - Helpers

    /// Away this long or more ⇒ no toast on return. The engine still emits `.awayDecision`
    /// (stats depend on it); only the surface is skipped.
    private static let awayToastCutoff: TimeInterval = 30 * 60

    private var snoozesRemaining: Int {
        min(engine.snoozesRemainingToday, engine.snoozesRemainingThisSession)
    }

    private static func symbol(for kind: BreakKind) -> String {
        kind == .long ? "figure.walk" : "eye"
    }

    private static func symbol(for hint: ActivityHint) -> String {
        switch hint {
        case .typing: return "keyboard"
        case .dragging: return "hand.draw"
        case .dictating: return "mic.fill"
        }
    }

    private static func minutesLabel(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes <= 0 { return "\(Int(seconds.rounded()))s" }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    // MARK: - Lock screen

    /// While the screen is locked the break overlay steps aside (its pinned space would otherwise
    /// cover loginwindow); it returns on unlock if the break is still running.
    private func installLockObservers() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil,
                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.overlay.suspend() }
        }
        center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil,
                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.engine.phase.isInBreak else { return }
                self.overlay.resume()
            }
        }
    }

    /// Locks the Mac once the overlay has finished fading in, so the fade is not cut in half.
    private func scheduleScreenLock() {
        let delay = OverlayMotion.duration(0.9) + 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Self.lockScreenNow()
        }
    }

    static func lockScreenNow() {
        // The only true lock (what ⌃⌘Q does) is SACLockScreenImmediate in the private login
        // framework — CGSession -suspend is gone on macOS 26, and `pmset displaysleepnow` merely
        // sleeps the display, which mouse movement undoes unless the user requires a password
        // immediately. Same guarded-private-API policy as SpacePinning: dlsym or degrade.
        typealias LockFn = @convention(c) () -> Int32
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY),
           let sym = dlsym(handle, "SACLockScreenImmediate") {
            _ = unsafeBitCast(sym, to: LockFn.self)()
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }
}
