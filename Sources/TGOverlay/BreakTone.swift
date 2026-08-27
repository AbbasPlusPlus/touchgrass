// TGOverlay — which ink the break screen draws with.
import AppKit
import SwiftUI
import TGCore

/// The break screen has two quite different canvases.
///
/// The default "screen blur" backdrop is a paper wash over the frosted desktop, and it follows
/// the system appearance — so in light mode the type has to be *dark*. The gradient, animated
/// and wallpaper backdrops are dark whatever the system is doing, so their type stays bone.
///
/// Rather than sample luminance (expensive, and wrong on a wallpaper with a bright corner),
/// the tone is decided by which backdrop is in use, exactly as DESIGN.md asks.
public enum BreakTone {

    /// Matte paper: follows the system appearance.
    case paper
    /// A dark backdrop: always the dark-mode ink.
    case dark

    public static func matching(_ background: BreakBackground) -> BreakTone {
        switch background {
        case .screenBlur:                       return .paper
        case .wallpaper, .gradient, .animated, .image:
            return .dark
        }
    }

    // MARK: - Ink

    var primary: Color {
        switch self {
        case .paper: return OverlayPalette.ink
        case .dark:  return OverlayPalette.inkOnDark.opacity(0.97)
        }
    }

    var secondary: Color {
        switch self {
        case .paper: return OverlayPalette.ink2
        case .dark:  return OverlayPalette.inkOnDark.opacity(0.80)
        }
    }

    var tertiary: Color {
        switch self {
        case .paper: return OverlayPalette.ink2.opacity(0.85)
        case .dark:  return OverlayPalette.inkOnDark.opacity(OverlayType.tertiaryOpacity)
        }
    }

    /// The countdown — the one numeral big enough to carry the accent.
    var numerals: Color {
        switch self {
        case .paper: return OverlayPalette.matchaDeep
        case .dark:  return OverlayPalette.inkOnDark.opacity(0.95)
        }
    }

    // MARK: - Chrome

    /// The hairline between the subtitle and the countdown, as a three-stop gradient.
    var hairline: [Color] {
        let mid: Color
        switch self {
        case .paper: mid = OverlayPalette.stone
        case .dark:  mid = OverlayPalette.inkOnDark.opacity(0.32)
        }
        return [mid.opacity(0), mid, mid.opacity(0)]
    }

    /// Fill behind the Esc keycap.
    var keycap: Color {
        switch self {
        case .paper: return OverlayPalette.stone.opacity(0.70)
        case .dark:  return OverlayPalette.inkOnDark.opacity(0.16)
        }
    }

    /// The corner grass strokes.
    var grass: Color {
        switch self {
        case .paper: return Color(nsColor: .ovGrass)
        case .dark:  return OverlayPalette.matchaOnDark.opacity(0.30)
        }
    }

    /// Outer shading, kept far softer on paper than on a dark backdrop.
    var vignette: Color {
        switch self {
        case .paper: return Color(nsColor: .ovVignette)
        case .dark:  return .black.opacity(0.30)
        }
    }

    /// Drop shadow under the big type. Paper needs almost none.
    var textShadow: Color {
        switch self {
        case .paper: return Color(nsColor: .ovTextShadow)
        case .dark:  return .black.opacity(0.30)
        }
    }

    // MARK: - Pills

    /// Label on a quiet (paper-glass) pill.
    var pillText: Color {
        switch self {
        case .paper: return OverlayPalette.ink
        case .dark:  return OverlayPalette.inkOnDark.opacity(0.95)
        }
    }

    /// Hairline around a quiet pill: stone on paper, bone on a dark backdrop.
    var pillBorder: Color {
        switch self {
        case .paper: return OverlayPalette.stone.opacity(0.85)
        case .dark:  return OverlayPalette.inkOnDark.opacity(0.22)
        }
    }

    /// The paper wash that sits over a quiet pill's glass.
    var pillWash: Color {
        switch self {
        case .paper: return OverlayPalette.glassWash
        case .dark:  return Color.tg(OverlayPalette.Hex.paper2Dark, opacity: 0.22)
        }
    }

    /// A quiet pill under Reduce Transparency.
    var pillFallback: Color {
        switch self {
        case .paper: return OverlayPalette.glassFallback
        case .dark:  return Color.tg(OverlayPalette.Hex.paper2Dark, opacity: 0.94)
        }
    }

    /// The one loud button: matcha fill…
    var primaryFill: Color {
        switch self {
        case .paper: return OverlayPalette.matcha
        case .dark:  return OverlayPalette.matchaOnDark
        }
    }

    /// …with paper type on it.
    var primaryText: Color {
        switch self {
        case .paper: return OverlayPalette.onMatcha
        case .dark:  return Color.tg(0x252A1E)
        }
    }

    /// Skip's balanced-delay ring. Clay, and only ever clay.
    var ring: Color {
        switch self {
        case .paper: return OverlayPalette.clay
        case .dark:  return Color.tg(OverlayPalette.Hex.clayDark)
        }
    }

    /// The brightening wash a pill picks up under the pointer.
    var hoverWash: Color {
        switch self {
        case .paper: return Color(nsColor: .ovHoverWash)
        case .dark:  return Color.tg(OverlayPalette.Hex.inkDark, opacity: 0.10)
        }
    }
}

// MARK: - Tone-only colours

extension NSColor {
    /// Grass strokes: matcha at 35% in light, 30% in dark (DESIGN.md).
    static let ovGrass = NSColor.ovDynamicAlpha("ovGrass",
                                                OverlayPalette.Hex.matchaLight, 0.35,
                                                OverlayPalette.Hex.matchaDark, 0.30)
    /// Vignette on paper: a warm shade in light, a plain darkening in dark.
    static let ovVignette = NSColor.ovDynamicAlpha("ovVignette",
                                                   OverlayPalette.Hex.inkLight, 0.10,
                                                   0x000000, 0.34)
    /// Shadow under paper-mode type.
    static let ovTextShadow = NSColor.ovDynamicAlpha("ovTextShadow",
                                                     OverlayPalette.Hex.inkLight, 0.10,
                                                     0x000000, 0.34)
    /// Hover wash: paper brightens a light surface, bone brightens a dark one.
    static let ovHoverWash = NSColor.ovDynamicAlpha("ovHoverWash",
                                                    0xFFFFFF, 0.34,
                                                    OverlayPalette.Hex.inkDark, 0.10)
}
