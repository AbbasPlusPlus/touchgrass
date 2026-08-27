// TGOverlay — the six gradient presets.
// Every palette is deliberately low-contrast and desaturated: a break screen should read as
// atmosphere, not as artwork. Luminance stays under ~35% so white type sits comfortably on top.
//
// Colours are stored as hex so both SwiftUI (`Color`) and Core Animation (`CGColor`) can have them.

import SwiftUI
import TGCore

public struct GradientPalette: Sendable {

    public struct Bloom: Sendable {
        public let hex: UInt32
        public let alpha: Double
        public init(_ hex: UInt32, _ alpha: Double) { self.hex = hex; self.alpha = alpha }
    }

    /// Vertical base wash, top → bottom.
    public let base: [UInt32]
    /// Two slow-drifting light blooms composited over the base.
    public let bloomA: Bloom
    public let bloomB: Bloom

    public init(base: [UInt32], bloomA: Bloom, bloomB: Bloom) {
        self.base = base
        self.bloomA = bloomA
        self.bloomB = bloomB
    }

    /// SwiftUI colours for the base wash — for settings-screen previews.
    public var baseColors: [Color] { base.map { Color.tg($0) } }
    /// Core Animation colours for the base wash — used by the break backdrop.
    var baseCGColors: [CGColor] { base.map { CGColor.tg($0) } }

    public static func palette(for preset: GradientPreset) -> GradientPalette {
        switch preset {
        case .dawn:                             // cold night giving way to a low sun
            return GradientPalette(base: [0x171A2B, 0x2B2740, 0x4E3A4A, 0x6E4A45],
                                   bloomA: Bloom(0xE0925F, 0.30),
                                   bloomB: Bloom(0x6C6BA8, 0.26))
        case .dusk:                             // the ten minutes after sunset
            return GradientPalette(base: [0x0F1119, 0x201B33, 0x392A4C, 0x4E3352],
                                   bloomA: Bloom(0x8C6BB8, 0.28),
                                   bloomB: Bloom(0xD07C86, 0.20))
        case .forest:                           // canopy light, deep and green
            return GradientPalette(base: [0x0C1412, 0x14231C, 0x1F3428, 0x2E4634],
                                   bloomA: Bloom(0x74A87A, 0.24),
                                   bloomB: Bloom(0xC7BE7A, 0.16))
        case .ocean:                            // deep water with a far-off surface glow
            return GradientPalette(base: [0x070F18, 0x0D2130, 0x143646, 0x1C4C5C],
                                   bloomA: Bloom(0x4FA8C4, 0.26),
                                   bloomB: Bloom(0x2E6E9E, 0.22))
        case .ember:                            // banked coals, warm but never bright
            return GradientPalette(base: [0x140F0D, 0x281611, 0x442117, 0x5E301C],
                                   bloomA: Bloom(0xE08A4A, 0.24),
                                   bloomB: Bloom(0xA84A38, 0.22))
        case .lavender:                         // dry lavender at last light
            return GradientPalette(base: [0x121019, 0x231D31, 0x362C4A, 0x4B3E5F],
                                   bloomA: Bloom(0xA894D6, 0.24),
                                   bloomB: Bloom(0x6E7FC0, 0.20))
        }
    }
}

// MARK: - Hex convenience

extension Color {
    /// 0xRRGGBB literal → Color.
    static func tg(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255.0,
              green: Double((hex >> 8) & 0xFF) / 255.0,
              blue: Double(hex & 0xFF) / 255.0,
              opacity: opacity)
    }
}

extension CGColor {
    /// 0xRRGGBB literal → CGColor in sRGB.
    static func tg(_ hex: UInt32, opacity: Double = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: CGFloat(opacity))
    }
}
