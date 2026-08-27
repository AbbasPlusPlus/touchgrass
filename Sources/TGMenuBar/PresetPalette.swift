// TGMenuBar — the colours behind the appearance swatches.
import SwiftUI
import TGCore

/// Two-stop palettes for the break-background pickers. TGOverlay renders the real thing;
/// these are the settings-window previews, kept in one place so they stay in sync by name.
enum PresetPalette {

    static func colors(_ preset: GradientPreset) -> [Color] {
        switch preset {
        case .dawn:     return [Color(red: 0.99, green: 0.76, blue: 0.60), Color(red: 0.79, green: 0.53, blue: 0.72)]
        case .dusk:     return [Color(red: 0.31, green: 0.29, blue: 0.55), Color(red: 0.85, green: 0.49, blue: 0.47)]
        case .forest:   return [Color(red: 0.19, green: 0.42, blue: 0.32), Color(red: 0.56, green: 0.72, blue: 0.44)]
        case .ocean:    return [Color(red: 0.13, green: 0.35, blue: 0.55), Color(red: 0.38, green: 0.74, blue: 0.78)]
        case .ember:    return [Color(red: 0.42, green: 0.13, blue: 0.16), Color(red: 0.93, green: 0.55, blue: 0.25)]
        case .lavender: return [Color(red: 0.55, green: 0.48, blue: 0.79), Color(red: 0.87, green: 0.79, blue: 0.93)]
        }
    }

    static func colors(_ preset: AnimatedPreset) -> [Color] {
        switch preset {
        case .slipstream: return [Color(red: 0.11, green: 0.16, blue: 0.34), Color(red: 0.35, green: 0.56, blue: 0.86)]
        case .fireflies:  return [Color(red: 0.06, green: 0.12, blue: 0.10), Color(red: 0.42, green: 0.56, blue: 0.28)]
        case .topography: return [Color(red: 0.16, green: 0.19, blue: 0.22), Color(red: 0.51, green: 0.57, blue: 0.60)]
        case .aurora:     return [Color(red: 0.07, green: 0.10, blue: 0.22), Color(red: 0.30, green: 0.80, blue: 0.68)]
        }
    }

    static func title(_ preset: GradientPreset) -> String { preset.rawValue.capitalized }
    static func title(_ preset: AnimatedPreset) -> String { preset.rawValue.capitalized }

    static func gradient(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
