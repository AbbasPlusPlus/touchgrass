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
        // Re-derived onto the Paper Garden palette: every base is pulled toward the warm
        // ink-green end, and every bloom is a palette hue (matcha, pollen, clay) rather than
        // an arbitrary one. The names, the moods and the luminance ceiling are unchanged —
        // bone type still has to sit on top of all six.
        switch preset {
        case .dawn:                             // warm ground, a low sun coming up
            return GradientPalette(base: [0x1A1C18, 0x2C2A22, 0x4A3A2C, 0x6B4A33],
                                   bloomA: Bloom(OverlayPalette.Hex.pollen, 0.28),
                                   bloomB: Bloom(OverlayPalette.Hex.clayLight, 0.24))
        case .dusk:                             // the ten minutes after sunset
            return GradientPalette(base: [0x14161A, 0x22222E, 0x3A3140, 0x50384A],
                                   bloomA: Bloom(0x8C6BB8, 0.26),
                                   bloomB: Bloom(OverlayPalette.Hex.clayDark, 0.20))
        case .forest:                           // canopy light — the matcha family, deepened
            return GradientPalette(base: [0x0E140F, 0x18231A, 0x243425, 0x35462F],
                                   bloomA: Bloom(OverlayPalette.Hex.matchaDark, 0.26),
                                   bloomB: Bloom(OverlayPalette.Hex.pollen, 0.16))
        case .ocean:                            // deep water with a far-off surface glow
            return GradientPalette(base: [0x08100F, 0x0E2128, 0x16363C, 0x1E4C50],
                                   bloomA: Bloom(0x4FA8B4, 0.26),
                                   bloomB: Bloom(0x3A6E86, 0.22))
        case .ember:                            // banked coals, warm but never bright
            return GradientPalette(base: [0x150F0C, 0x2A1710, 0x452216, 0x5E301C],
                                   bloomA: Bloom(0xE08A4A, 0.24),
                                   bloomB: Bloom(0xA84A38, 0.22))
        case .lavender:                         // dry lavender at last light
            return GradientPalette(base: [0x131118, 0x241E30, 0x372D48, 0x4C3F5C],
                                   bloomA: Bloom(0xA894D6, 0.24),
                                   bloomB: Bloom(0x7C8AAE, 0.20))
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
