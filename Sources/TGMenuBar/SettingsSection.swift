// TGMenuBar — the settings sidebar's table of contents.
import SwiftUI

/// One page of the settings window. Grouped exactly like  (and System Settings):
/// what the app does to you, then how it behaves, then the housekeeping.
public enum SettingsSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case screenBreaks
    case smartPause
    case wellness
    case alerts
    case appearance
    case sounds
    case shortcuts
    case general
    case about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .screenBreaks: return "Screen Breaks"
        case .smartPause:   return "Smart Pause"
        case .wellness:     return "Wellness"
        case .alerts:       return "Alerts & Nudges"
        case .appearance:   return "Appearance"
        case .sounds:       return "Sounds"
        case .shortcuts:    return "Keyboard Shortcuts"
        case .general:      return "General"
        case .about:        return "About"
        }
    }

    /// One line under the page title — what this page is for, in plain words.
    var blurb: String {
        switch self {
        case .screenBreaks: return "How often your eyes get a rest, and how firmly TouchGrass insists."
        case .smartPause:   return "When TouchGrass should stay out of your way."
        case .wellness:     return "Small nudges between the breaks."
        case .alerts:       return "The warning you get before a break arrives."
        case .appearance:   return "What the break screen looks like."
        case .sounds:       return "A soft exhale, never an alarm."
        case .shortcuts:    return "Drive TouchGrass from anywhere, without touching the menu bar."
        case .general:      return "Startup, the menu bar, and the app itself."
        case .about:        return "Version, links, and what TouchGrass does not ask for."
        }
    }

    var symbol: String {
        switch self {
        case .screenBreaks: return "timer"
        case .smartPause:   return "pause.circle"
        case .wellness:     return "eye"
        case .alerts:       return "bell"
        case .appearance:   return "paintpalette"
        case .sounds:       return "speaker.wave.2"
        case .shortcuts:    return "keyboard"
        case .general:      return "gear"
        case .about:        return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .screenBreaks: return .pink
        case .smartPause:   return .purple
        case .wellness:     return .green
        case .alerts:       return .orange
        case .appearance:   return .blue
        case .sounds:       return .teal
        case .shortcuts:    return .gray
        case .general:      return .gray
        case .about:        return .gray
        }
    }

    /// Sidebar groups, in order. An empty header renders as an ungrouped block.
    static let groups: [(header: String, sections: [SettingsSection])] = [
        ("Focus & Wellbeing", [.screenBreaks, .smartPause, .wellness]),
        ("Behavior & Feedback", [.alerts, .appearance, .sounds, .shortcuts]),
        ("", [.general, .about]),
    ]
}
