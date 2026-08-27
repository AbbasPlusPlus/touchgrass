// TGMenuBar — the vocabulary of globally hotkey-able commands.
import Foundation

/// Every command that can be bound to a global keyboard shortcut.
/// `rawValue` is the persistence key inside `Settings.hotkeys`.
public enum HotkeyAction: String, CaseIterable, Sendable, Hashable {
    case togglePause      = "togglePause"
    case startBreak       = "startBreak"
    case startLongBreak   = "startLongBreak"
    case addMinute        = "addMinute"
    case skipOrEndBreak   = "skipOrEndBreak"
    case openQuickPanel   = "openQuickPanel"

    public var title: String {
        switch self {
        case .togglePause:    return "Toggle pause"
        case .startBreak:     return "Start break now"
        case .startLongBreak: return "Start long break"
        case .addMinute:      return "Add 1 minute"
        case .skipOrEndBreak: return "Skip / end break"
        case .openQuickPanel: return "Open quick panel"
        }
    }

    public var subtitle: String {
        switch self {
        case .togglePause:    return "Pause or resume TouchGrass"
        case .startBreak:     return "Begin a short break immediately"
        case .startLongBreak: return "Begin a long break immediately"
        case .addMinute:      return "Push the next break back by a minute"
        case .skipOrEndBreak: return "Dismiss the break that's showing"
        case .openQuickPanel: return "Show the menu bar panel"
        }
    }

    public var symbolName: String {
        switch self {
        case .togglePause:    return "pause.circle"
        case .startBreak:     return "cup.and.saucer"
        case .startLongBreak: return "figure.walk"
        case .addMinute:      return "plus.circle"
        case .skipOrEndBreak: return "forward.end"
        case .openQuickPanel: return "menubar.arrow.down.rectangle"
        }
    }

    /// Stable display order for the shortcuts settings page.
    public static let displayOrder: [HotkeyAction] = [
        .togglePause, .startBreak, .startLongBreak, .addMinute, .skipOrEndBreak, .openQuickPanel,
    ]
}
