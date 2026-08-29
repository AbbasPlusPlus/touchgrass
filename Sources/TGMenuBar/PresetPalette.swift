// TGMenuBar — the colours behind the appearance swatches.
import SwiftUI
import TGCore

/// Two-stop palettes for the break-background pickers. TGOverlay renders the real thing;
/// these are the settings-window previews, kept in one place so they stay in sync by name.
///
/// Each pair is the *top* of the real backdrop's base wash and the hue of its brighter bloom —
/// a 78×48 tile of the actual base colours would be six near-identical near-blacks.
enum PresetPalette {

    static func colors(_ preset: GradientPreset) -> [Color] {
        switch preset {
        case .dawn:     return [.tg(0x6B4A33), .tg(0xD8B45E)]
        case .dusk:     return [.tg(0x50384A), .tg(0x8C6BB8)]
        case .forest:   return [.tg(0x35462F), .tg(0x8BA579)]
        case .ocean:    return [.tg(0x1E4C50), .tg(0x4FA8B4)]
        case .ember:    return [.tg(0x5E301C), .tg(0xE08A4A)]
        case .lavender: return [.tg(0x4C3F5C), .tg(0xA894D6)]
        }
    }

    static func colors(_ preset: AnimatedPreset) -> [Color] {
        switch preset {
        case .slipstream: return [.tg(0x122436), .tg(0x64A5B4)]
        case .fireflies:  return [.tg(0x14201C), .tg(0xE6F0AE)]
        case .topography: return [.tg(0x1D2432), .tg(0xAEC8EA)]
        case .aurora:     return [.tg(0x111C2E), .tg(0x66E0A8)]
        case .bokeh:      return [.tg(0x1E1922), .tg(0xE8B27A)]
        case .rain:       return [.tg(0x0F1B30), .tg(0xAECBE6)]
        case .ripple:     return [.tg(0x0E141C), .tg(0xBCD6E6)]
        case .lanterns:   return [.tg(0x2A1840), .tg(0xFFC97A)]
        }
    }

    static func title(_ preset: GradientPreset) -> String { preset.rawValue.capitalized }
    static func title(_ preset: AnimatedPreset) -> String { preset.rawValue.capitalized }

    static func gradient(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
