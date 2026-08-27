// TGCore — BreakEngine: the state machine. STUB — to be implemented by the core agent.
// Contract: @MainActor ObservableObject. Driven by `tick()` (called ~1×/s by the app) plus
// commands from UI and signal updates from detectors. Emits EngineEvents; never touches UI.
import Foundation
import Combine

@MainActor
public final class BreakEngine: ObservableObject {
    @Published public private(set) var phase: EnginePhase = .stopped
    /// Snoozes used today / this session (session = since last completed break).
    @Published public private(set) var snoozesUsedToday: Int = 0
    @Published public private(set) var snoozesUsedThisSession: Int = 0
    /// Focus time accumulated in the current session (seconds of unpaused screen time).
    @Published public private(set) var currentSessionFocusTime: TimeInterval = 0
    /// Short breaks completed since the last long break (drives "every Nth is long").
    @Published public private(set) var shortBreaksSinceLong: Int = 0

    public let events = PassthroughSubject<EngineEvent, Never>()

    public var settings: Settings
    private let clock: Clock

    public init(settings: Settings, clock: Clock = SystemClock()) {
        self.settings = settings
        self.clock = clock
    }

    // MARK: Lifecycle
    public func start() { fatalError("unimplemented") }
    public func stop() { fatalError("unimplemented") }
    /// Advance the machine. Uses `clock.now()` so it's robust to sleep (wall-clock deltas, not tick counts).
    public func tick() { fatalError("unimplemented") }

    // MARK: Commands (from menu bar / overlay / hotkeys)
    public func startBreakNow(_ kind: BreakKind) { fatalError("unimplemented") }
    public func startCustomBreak(duration: TimeInterval) { fatalError("unimplemented") }
    public func snooze(_ seconds: TimeInterval) { fatalError("unimplemented") }
    public func skipBreak() { fatalError("unimplemented") }
    public func endBreakEarly() { fatalError("unimplemented") }
    public func pauseManually(for duration: TimeInterval?) { fatalError("unimplemented") }
    public func resumeManually() { fatalError("unimplemented") }
    public func addMinute() { fatalError("unimplemented") }
    /// Undo the last automatic away decision (toast "Undo").
    public func undoAwayDecision() { fatalError("unimplemented") }

    // MARK: Signals (from TGDetection)
    public func updatePauseReasons(_ reasons: Set<PauseReason>) { fatalError("unimplemented") }
    public func updateActivityHint(_ hint: ActivityHint?) { fatalError("unimplemented") }
    public func updateIdleSeconds(_ seconds: TimeInterval) { fatalError("unimplemented") }
    public func screenDidLock() { fatalError("unimplemented") }
    public func screenDidUnlock() { fatalError("unimplemented") }
    public func systemDidWake() { fatalError("unimplemented") }

    // MARK: Derived
    public var canSkipNow: Bool { false }
    public var snoozesRemainingToday: Int { max(0, settings.snoozesPerDay - snoozesUsedToday) }
    public var snoozesRemainingThisSession: Int { max(0, settings.snoozesPerSession - snoozesUsedThisSession) }
}
