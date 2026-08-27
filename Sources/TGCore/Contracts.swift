// TGCore — shared vocabulary between all modules. Pure Swift, no AppKit.
// Everything the detectors produce, the engine consumes, and the UI renders passes through these types.
// CHANGE WITH CARE: several modules are built in parallel against this file.

import Foundation

// MARK: - Break kinds

public enum BreakKind: String, Codable, Sendable, Hashable, CaseIterable {
    case short
    case long
}

// MARK: - Reasons the engine is auto-paused (the "Smart Pause" system)

/// Why breaks are currently being deferred. Detectors publish a Set of these; the engine freezes
/// focus-time accounting while the set is non-empty. `appName` is the human-readable app for UI copy
/// ("Call detected on Zoom"), `bundleID` for exclusion lists.
public enum PauseReason: Codable, Sendable, Hashable {
    case meeting(appName: String?, bundleID: String?)
    case video(appName: String?, bundleID: String?)
    case fullscreenApp(appName: String, bundleID: String?)
    case deepFocusApp(appName: String, bundleID: String?)
    case idle                       // user away; engine decides reset vs resume via Settings.idle*
    case manual(until: Date?)       // user-initiated pause; nil = indefinite
    case focusMode                  // macOS Focus active (optional feature)
    case screenLocked

    /// Short label for the menu bar: "Paused · Meeting".
    public var shortLabel: String {
        switch self {
        case .meeting: return "Meeting"
        case .video: return "Video"
        case .fullscreenApp: return "Fullscreen"
        case .deepFocusApp: return "Deep focus"
        case .idle: return "Away"
        case .manual: return "Paused"
        case .focusMode: return "Focus"
        case .screenLocked: return "Locked"
        }
    }

    /// Full sentence for toasts: "Call detected on Zoom — TouchGrass is paused".
    public var toastText: String {
        switch self {
        case .meeting(let app, _): return "Call detected\(app.map { " on \($0)" } ?? "")"
        case .video(let app, _): return "Video detected\(app.map { " on \($0)" } ?? "")"
        case .fullscreenApp(let app, _): return "\(app) is fullscreen"
        case .deepFocusApp(let app, _): return "\(app) is a deep focus app"
        case .idle: return "You stepped away"
        case .manual: return "Paused"
        case .focusMode: return "Focus mode is on"
        case .screenLocked: return "Screen locked"
        }
    }
}

// MARK: - Short-lived activity that *delays* a break rather than pausing the timer

/// Typing / dragging / dictating in the final seconds before a break. The engine waits for this to
/// clear (+ a short buffer) before showing the break. Does NOT freeze focus time.
public enum ActivityHint: String, Codable, Sendable, Hashable {
    case typing
    case dragging
    case dictating

    public var label: String {
        switch self {
        case .typing: return "Typing…"
        case .dragging: return "Dragging…"
        case .dictating: return "Dictating…"
        }
    }
}

// MARK: - Engine state

public enum EnginePhase: Sendable, Equatable {
    /// User stopped TouchGrass entirely (menu bar shows stopped icon).
    case stopped
    /// Counting focus time toward the next break.
    case running(nextBreak: BreakKind, remaining: TimeInterval)
    /// Within `Settings.preBreakWarningSeconds` of a break; UI shows the notification card.
    case preBreak(kind: BreakKind, remaining: TimeInterval)
    /// Break is due but an ActivityHint is active; UI shows "Typing…" pill.
    case waitingForActivityToStop(kind: BreakKind, hint: ActivityHint)
    /// Break overlay is up.
    case inBreak(kind: BreakKind, remaining: TimeInterval, total: TimeInterval)
    /// Focus time frozen. `remaining` is what will be left when resumed.
    case paused(reasons: Set<PauseReason>, nextBreak: BreakKind, remaining: TimeInterval)

    public var isInBreak: Bool { if case .inBreak = self { return true }; return false }
    public var isPaused: Bool { if case .paused = self { return true }; return false }
}

/// Discrete events for UI/audio side effects. The engine emits these; it never touches UI itself.
public enum EngineEvent: Sendable, Equatable {
    case preBreakWarning(kind: BreakKind, startsIn: TimeInterval)   // show the card (T-60s by default)
    case preBreakCountdown(kind: BreakKind, secondsLeft: Int)      // cursor pill ticks (T-10..T-1)
    case breakStarted(kind: BreakKind, duration: TimeInterval)
    case breakTick(kind: BreakKind, remaining: TimeInterval)
    case breakEnded(kind: BreakKind, completed: Bool)              // completed=false when skipped/ended early
    case snoozed(kind: BreakKind, by: TimeInterval)
    case skipped(kind: BreakKind)
    case paused(reasons: Set<PauseReason>)
    case resumed
    case awayDecision(resetTimer: Bool, awayFor: TimeInterval)     // for the silent toast w/ undo
    case wellnessReminder(WellnessKind)
}

public enum WellnessKind: String, Codable, Sendable, Hashable, CaseIterable {
    case blink
    case posture
}

// MARK: - Enforcement

public enum Enforcement: String, Codable, Sendable, Hashable, CaseIterable {
    /// Skip anytime.
    case casual
    /// Skip button enabled after `Settings.balancedSkipDelaySeconds`.
    case balanced
    /// No skip. (Snooze still possible from the pre-break card if snoozes remain.)
    case hardcore

    public var title: String {
        switch self {
        case .casual: return "Casual"
        case .balanced: return "Balanced"
        case .hardcore: return "Hardcore"
        }
    }
    public var subtitle: String {
        switch self {
        case .casual: return "Skip anytime"
        case .balanced: return "Skip after a pause"
        case .hardcore: return "No skips allowed"
        }
    }
}

// MARK: - Overlay appearance

public enum BreakBackground: Codable, Sendable, Hashable {
    case wallpaper                 // the user's real desktop picture per screen, blurred
    case gradient(GradientPreset)
    case animated(AnimatedPreset)
    case image(path: String)
}

public enum GradientPreset: String, Codable, Sendable, Hashable, CaseIterable {
    case dawn, dusk, forest, ocean, ember, lavender
}

public enum AnimatedPreset: String, Codable, Sendable, Hashable, CaseIterable {
    case slipstream, fireflies, topography, aurora
}

public enum SoundStyle: String, Codable, Sendable, Hashable, CaseIterable {
    case bell        // Tibetan singing bowl
    case chime
    case flute
    case none

    public var title: String {
        switch self {
        case .bell: return "Singing bowl"
        case .chime: return "Chime"
        case .flute: return "Flute"
        case .none: return "None"
        }
    }
}

// MARK: - Clock abstraction (lets tests drive time deterministically)

public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}
