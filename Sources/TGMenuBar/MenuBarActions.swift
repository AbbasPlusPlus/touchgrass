// TGMenuBar — the command surface shared by the status menu, the quick panel and the hotkeys.
import Foundation
import TGCore

/// Every user-initiated command the menu bar can issue, as closures.
///
/// The UI never calls `BreakEngine` directly: `StatusBarController` owns the engine and builds
/// this struct. That keeps all engine calls on genuine user-action paths (the engine's methods
/// are not safe to call speculatively) and makes the views trivially previewable in the demo.
public struct MenuBarActions {
    public var startBreak: (BreakKind) -> Void
    /// A one-off break of an arbitrary length — the menu's "Take a break for ▸".
    public var startCustomBreak: (TimeInterval) -> Void
    /// "+1m" / "+5m" / "+15m" — pushes the next break back.
    public var delay: (TimeInterval) -> Void
    /// Skip the pending break, or end the running one early.
    public var skipOrEnd: () -> Void
    /// `nil` duration = pause indefinitely.
    public var pause: (TimeInterval?) -> Void
    public var resume: () -> Void
    public var toggleRunning: () -> Void
    public var openSettings: () -> Void
    public var openOnboarding: () -> Void
    public var quit: () -> Void

    public init(
        startBreak: @escaping (BreakKind) -> Void = { _ in },
        startCustomBreak: @escaping (TimeInterval) -> Void = { _ in },
        delay: @escaping (TimeInterval) -> Void = { _ in },
        skipOrEnd: @escaping () -> Void = {},
        pause: @escaping (TimeInterval?) -> Void = { _ in },
        resume: @escaping () -> Void = {},
        toggleRunning: @escaping () -> Void = {},
        openSettings: @escaping () -> Void = {},
        openOnboarding: @escaping () -> Void = {},
        quit: @escaping () -> Void = {}
    ) {
        self.startBreak = startBreak
        self.startCustomBreak = startCustomBreak
        self.delay = delay
        self.skipOrEnd = skipOrEnd
        self.pause = pause
        self.resume = resume
        self.toggleRunning = toggleRunning
        self.openSettings = openSettings
        self.openOnboarding = openOnboarding
        self.quit = quit
    }
}

/// Pause presets offered by both the right-click menu and the quick panel's pause button.
public enum PausePreset: CaseIterable, Sendable {
    case fifteenMinutes
    case oneHour
    case untilTomorrow
    case indefinitely

    public var title: String {
        switch self {
        case .fifteenMinutes: return "For 15 minutes"
        case .oneHour: return "For 1 hour"
        case .untilTomorrow: return "Until tomorrow"
        case .indefinitely: return "Indefinitely"
        }
    }

    /// Shorter form for a submenu, where "Pause breaks ▸" already supplies the verb.
    public var menuTitle: String {
        switch self {
        case .fifteenMinutes: return "15 minutes"
        case .oneHour: return "1 hour"
        case .untilTomorrow: return "Until tomorrow"
        case .indefinitely: return "Indefinitely"
        }
    }

    /// Seconds from now, or nil for an open-ended pause.
    public func duration(from now: Date = Date(), calendar: Calendar = .current) -> TimeInterval? {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .oneHour: return 60 * 60
        case .untilTomorrow:
            let tomorrow = calendar.startOfDay(for: now.addingTimeInterval(24 * 60 * 60))
            return max(60, tomorrow.timeIntervalSince(now))
        case .indefinitely: return nil
        }
    }
}
