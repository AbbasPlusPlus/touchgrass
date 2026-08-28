// TGOverlay — the "Paper Garden" palette.
import AppKit
import SwiftUI

/// Every colour the overlay surfaces use, as a light/dark pair.
///
/// Built on `NSColor(name:dynamicProvider:)` so the tokens re-resolve when the system flips
/// appearance, without the overlay having to watch for it.
///
/// Mirrors `TGMenuBar.TGPalette` name-for-name — the two modules don't depend on each other,
/// so the palette is duplicated rather than shared. Keep the shared names in step.
public enum OverlayPalette {

    // MARK: - Tokens

    public static let paper = Color(nsColor: .ovPaper)
    public static let paper2 = Color(nsColor: .ovPaper2)
    public static let stone = Color(nsColor: .ovStone)
    public static let ink = Color(nsColor: .ovInk)
    public static let ink2 = Color(nsColor: .ovInk2)
    public static let matcha = Color(nsColor: .ovMatcha)
    public static let matchaDeep = Color(nsColor: .ovMatchaDeep)
    public static let clay = Color(nsColor: .ovClay)
    /// A second step of the matcha family — the dark-mode end of the wellness badge gradient.
    public static let moss = Color(nsColor: .ovMoss)
    public static let onMatcha = Color(nsColor: .ovOnMatcha)
    public static let pollen = Color.tg(Hex.pollen)

    // MARK: - Fixed-mode values

    // The break screen's gradient and wallpaper backdrops are dark whatever the system is
    // doing, so anything drawn on them uses the dark-mode ink directly rather than a token
    // that would go near-black the moment the user switches to light appearance.

    /// Bone — the dark-mode ink, used as a literal on dark backdrops.
    public static let inkOnDark = Color.tg(Hex.inkDark)
    /// The dark-mode secondary ink, likewise.
    public static let ink2OnDark = Color.tg(Hex.ink2Dark)
    /// Matcha as it appears against a dark backdrop.
    public static let matchaOnDark = Color.tg(Hex.matchaDark)

    // MARK: - Glass

    /// The paper wash that keeps Liquid Glass reading warm instead of gray.
    public static let glassWash = Color(nsColor: .ovGlassWash)
    /// A stronger wash, for the "prominent" tier of pill.
    public static let glassWashStrong = Color(nsColor: .ovGlassWashStrong)
    /// The hairline around a glass surface: a bright rim in light mode, a bone one in dark.
    public static let glassRim = Color(nsColor: .ovGlassRim)
    /// What every glass surface becomes under Reduce Transparency.
    public static let glassFallback = Color(nsColor: .ovGlassFallback)

    // MARK: - Break-screen washes

    /// Laid over the frosted desktop in light appearance (DESIGN.md: warm off-white, 30%).
    public static let frostWashLight = Color.tg(Hex.paperLight, opacity: 0.30)
    /// …and in dark appearance (deep ink-green, 32%).
    public static let frostWashDark = Color.tg(Hex.inkGreenWash, opacity: 0.32)

    // MARK: - Hex table

    /// The palette's raw values, so `CGColor`-land (Core Animation backdrops) can have them too.
    public enum Hex {
        public static let paperLight: UInt32 = 0xF2EEDE
        public static let paperDark: UInt32 = 0x20241D
        public static let paper2Light: UInt32 = 0xFAF7EC
        public static let paper2Dark: UInt32 = 0x2A2F26
        public static let stoneLight: UInt32 = 0xE3DCC8
        public static let stoneDark: UInt32 = 0x383E32
        public static let inkLight: UInt32 = 0x3D443A
        public static let inkDark: UInt32 = 0xE7E2D0
        public static let ink2Light: UInt32 = 0x6E7361
        public static let ink2Dark: UInt32 = 0xA9AC97
        public static let matchaLight: UInt32 = 0x5F7355
        public static let matchaDark: UInt32 = 0x8BA579
        public static let matchaDeepLight: UInt32 = 0x47563F
        public static let matchaDeepDark: UInt32 = 0xDFE4C8
        public static let clayLight: UInt32 = 0xB06A56
        public static let clayDark: UInt32 = 0xC98A74
        public static let pollen: UInt32 = 0xD8B45E
        /// The dark break-screen wash — paper's ink-green, pulled a shade deeper.
        public static let inkGreenWash: UInt32 = 0x161A13
    }

    // MARK: - Appearance

    /// Whether the *system* is in dark mode. Used where a surface has to pick a fixed value
    /// (a `CGColor`, an `NSVisualEffectView` material) rather than a dynamic colour.
    @MainActor
    public static var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

// MARK: - Dynamic NSColors

extension NSColor {

    static let ovPaper      = NSColor.ovDynamic("ovPaper",      OverlayPalette.Hex.paperLight,      OverlayPalette.Hex.paperDark)
    static let ovPaper2     = NSColor.ovDynamic("ovPaper2",     OverlayPalette.Hex.paper2Light,     OverlayPalette.Hex.paper2Dark)
    static let ovStone      = NSColor.ovDynamic("ovStone",      OverlayPalette.Hex.stoneLight,      OverlayPalette.Hex.stoneDark)
    static let ovInk        = NSColor.ovDynamic("ovInk",        OverlayPalette.Hex.inkLight,        OverlayPalette.Hex.inkDark)
    static let ovInk2       = NSColor.ovDynamic("ovInk2",       OverlayPalette.Hex.ink2Light,       OverlayPalette.Hex.ink2Dark)
    static let ovMatcha     = NSColor.ovDynamic("ovMatcha",     OverlayPalette.Hex.matchaLight,     OverlayPalette.Hex.matchaDark)
    static let ovMatchaDeep = NSColor.ovDynamic("ovMatchaDeep", OverlayPalette.Hex.matchaDeepLight, OverlayPalette.Hex.matchaDeepDark)
    static let ovClay       = NSColor.ovDynamic("ovClay",       OverlayPalette.Hex.clayLight,       OverlayPalette.Hex.clayDark)
    static let ovOnMatcha   = NSColor.ovDynamic("ovOnMatcha",   0xF3F1E2,                           0x252A1E)
    static let ovMoss       = NSColor.ovDynamic("ovMoss",       0x4F6B4A,                           0x7D9A6C)

    static let ovGlassWash = NSColor.ovDynamicAlpha("ovGlassWash",
                                                    OverlayPalette.Hex.paper2Light, 0.24,
                                                    OverlayPalette.Hex.paper2Dark, 0.22)
    static let ovGlassWashStrong = NSColor.ovDynamicAlpha("ovGlassWashStrong",
                                                          OverlayPalette.Hex.paper2Light, 0.46,
                                                          OverlayPalette.Hex.paper2Dark, 0.40)
    static let ovGlassRim = NSColor.ovDynamicAlpha("ovGlassRim",
                                                   0xFFFFFF, 0.45,
                                                   OverlayPalette.Hex.inkDark, 0.14)
    static let ovGlassFallback = NSColor.ovDynamicAlpha("ovGlassFallback",
                                                        OverlayPalette.Hex.paper2Light, 0.97,
                                                        OverlayPalette.Hex.paper2Dark, 0.97)

    static func ovDynamic(_ name: String, _ light: UInt32, _ dark: UInt32) -> NSColor {
        ovDynamicAlpha(name, light, 1, dark, 1)
    }

    static func ovDynamicAlpha(_ name: String,
                               _ light: UInt32, _ lightAlpha: CGFloat,
                               _ dark: UInt32, _ darkAlpha: CGFloat) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor.ovHex(dark, alpha: darkAlpha)
                : NSColor.ovHex(light, alpha: lightAlpha)
        }
    }

    static func ovHex(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }
}
