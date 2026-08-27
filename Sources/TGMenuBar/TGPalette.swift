// TGMenuBar — the "Paper Garden" palette.
import AppKit
import SwiftUI

/// Every colour the menu-bar surfaces use, as a light/dark pair.
///
/// Built on `NSColor(name:dynamicProvider:)` rather than SwiftUI's asset colours: the quick
/// panel, the settings window and the onboarding window are all AppKit windows hosting SwiftUI,
/// and a dynamic `NSColor` re-resolves the moment the system flips appearance — no reload, no
/// observer, and the same token works for `window.backgroundColor` as for a SwiftUI `.fill`.
///
/// `TGOverlay` keeps its own copy (`OverlayPalette`) with the same names, because the two
/// modules don't depend on each other. Keep the two in step.
enum TGPalette {

    // MARK: - Tokens

    /// The canvas. Settings and onboarding windows sit on this.
    static let paper = color(.tgPaper)
    /// A raised sheet: cards, rows, the Reduce-Transparency stand-in for glass.
    static let paper2 = color(.tgPaper2)
    /// Hairlines and quiet borders.
    static let stone = color(.tgStone)
    /// Primary text.
    static let ink = color(.tgInk)
    /// Secondary text. Never used below full strength — it is already the quiet tier.
    static let ink2 = color(.tgInk2)
    /// The one brand hue: primary buttons, selection, the gauge's cold end.
    static let matcha = color(.tgMatcha)
    /// Big numerals — a touch deeper than matcha in light mode, paler in dark.
    static let matchaDeep = color(.tgMatchaDeep)
    /// A second step of the matcha family, for sidebar icons that need to differ without
    /// introducing a new hue.
    static let moss = color(.tgMoss)
    /// Skip rings and destructive actions only.
    static let clay = color(.tgClay)
    /// The gauge's warm end. One value for both modes — it is a highlight, not a surface.
    static let pollen = Color(nsColor: .tgPollen)
    /// Text drawn *on* a matcha fill.
    static let onMatcha = color(.tgOnMatcha)

    // MARK: - Derived

    /// The wash laid over (and under) glass so the material reads warm rather than gray.
    static let glassWash = color(.tgPaper2).opacity(0.30)
    /// Row fill inside the quick panel — paper2 at just over half strength, per the mock-ups.
    static let rowFill = color(.tgPaper2).opacity(0.55)
    /// What a row becomes under the pointer.
    static let rowHoverFill = color(.tgStone).opacity(0.40)

    // MARK: - Motion

    /// Every hover transition in this module.
    static let hover: Animation = .easeOut(duration: 0.12)

    /// Collapses hover motion when Reduce Motion is on — the *state* still changes, only the
    /// tween goes away, so a hover is still visible to someone who asked for less movement.
    static func hoverAnimation() -> Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : hover
    }

    // MARK: - Plumbing

    private static func color(_ nsColor: NSColor) -> Color { Color(nsColor: nsColor) }
}

// MARK: - Dynamic NSColors

extension NSColor {

    static let tgPaper      = NSColor.tgDynamic("tgPaper",      light: 0xF2EEDE, dark: 0x20241D)
    static let tgPaper2     = NSColor.tgDynamic("tgPaper2",     light: 0xFAF7EC, dark: 0x2A2F26)
    static let tgStone      = NSColor.tgDynamic("tgStone",      light: 0xE3DCC8, dark: 0x383E32)
    static let tgInk        = NSColor.tgDynamic("tgInk",        light: 0x3D443A, dark: 0xE7E2D0)
    static let tgInk2       = NSColor.tgDynamic("tgInk2",       light: 0x6E7361, dark: 0xA9AC97)
    static let tgMatcha     = NSColor.tgDynamic("tgMatcha",     light: 0x5F7355, dark: 0x8BA579)
    static let tgMatchaDeep = NSColor.tgDynamic("tgMatchaDeep", light: 0x47563F, dark: 0xDFE4C8)
    static let tgClay       = NSColor.tgDynamic("tgClay",       light: 0xB06A56, dark: 0xC98A74)
    static let tgMoss       = NSColor.tgDynamic("tgMoss",       light: 0x4F6B4A, dark: 0x7D9A6C)
    static let tgOnMatcha   = NSColor.tgDynamic("tgOnMatcha",   light: 0xF3F1E2, dark: 0x252A1E)
    static let tgPollen     = NSColor.tgHex(0xD8B45E)

    /// A colour that re-resolves whenever the view it is drawn into changes appearance.
    static func tgDynamic(_ name: String, light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor.tgHex(dark)
                : NSColor.tgHex(light)
        }
    }

    /// 0xRRGGBB literal → sRGB NSColor.
    static func tgHex(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }
}

// MARK: - Hex convenience

extension Color {
    /// 0xRRGGBB literal → Color. Static colours only; dynamic ones go through `TGPalette`.
    static func tg(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255,
              opacity: opacity)
    }
}
