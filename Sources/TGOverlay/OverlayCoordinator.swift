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
            card.show(kind: kind,
                      secondsLeft: Int(startsIn.rounded()),
                      snoozesRemaining: snoozesRemaining,
                      visibleSeconds: settings.preBreakCardVisibleSeconds)
            if settings.soundOnPreBreak {
                sound.play(settings.soundStyle, event: .preBreak, volume: settings.volume)
            }

        case .preBreakCountdown(let kind, let secondsLeft):
            pendingKind = kind
            card.update(secondsLeft: secondsLeft, snoozesRemaining: snoozesRemaining)
            let label = "\(kind == .long ? "Long" : "Short") break in \(max(0, secondsLeft))"
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

        case .paused(let reasons):
            guard let reason = Self.toastableReason(in: reasons) else { break }
            card.hide()
            pill.hide()
            toast.show(symbol: Self.symbol(for: reason), text: reason.toastText)

        case .resumed:
            break

        case .awayDecision(let resetTimer, let awayFor):
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
        }
    }

    // MARK: - Phase

    private func handle(phase: EnginePhase) {
        defer { lastPhase = phase }

        switch phase {
        case .waitingForActivityToStop(_, let hint):
            if pill.isShowing {
                pill.update(symbol: "keyboard", text: hint.label)
            } else {
                pill.show(symbol: "keyboard", text: hint.label)
            }

        case .running, .stopped:
            pill.hide()
            card.hide()

        case .preBreak, .inBreak, .paused:
            break
        }
    }

    // MARK: - Helpers

    private var snoozesRemaining: Int {
        min(engine.snoozesRemainingToday, engine.snoozesRemainingThisSession)
    }

    private static func symbol(for kind: BreakKind) -> String {
        kind == .long ? "figure.walk" : "eye"
    }

    private static func symbol(for reason: PauseReason) -> String {
        switch reason {
        case .meeting: return "person.2.wave.2.fill"
        case .video: return "play.rectangle.fill"
        case .fullscreenApp: return "rectangle.inset.filled"
        case .deepFocusApp: return "moon.fill"
        default: return "pause.circle.fill"
        }
    }

    /// Idle and manual pauses are deliberately silent — 's loudest complaint was toast spam.
    private static func toastableReason(in reasons: Set<PauseReason>) -> PauseReason? {
        let ranked = reasons.filter {
            switch $0 {
            case .meeting, .video, .fullscreenApp, .deepFocusApp: return true
            default: return false
            }
        }
        // Deterministic priority: a call beats a video beats a fullscreen app beats a focus app.
        func rank(_ reason: PauseReason) -> Int {
            switch reason {
            case .meeting: return 0
            case .video: return 1
            case .fullscreenApp: return 2
            case .deepFocusApp: return 3
            default: return 4
            }
        }
        return ranked.min { rank($0) < rank($1) }
    }

    private static func minutesLabel(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes <= 0 { return "\(Int(seconds.rounded()))s" }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    // MARK: - Lock screen

    /// Locks the Mac once the overlay has finished fading in, so the fade is not cut in half.
    private func scheduleScreenLock() {
        let delay = OverlayMotion.duration(0.9) + 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let tool = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
            guard FileManager.default.isExecutableFile(atPath: tool) else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = ["-suspend"]
            try? process.run()
        }
    }
}
