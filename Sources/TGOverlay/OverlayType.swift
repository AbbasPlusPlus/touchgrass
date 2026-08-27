// TGOverlay — the type scale.
import SwiftUI

/// One place for every size and weight the overlay surfaces use.
///
/// Everything is SF Rounded. The break screen is read from across a desk while you are
/// deliberately *not* focusing, so its scale runs a long way above the base scale: a 52 pt
/// title over a 100 pt countdown.
///
/// The first block mirrors `TGMenuBar.TGType` name-for-name — the two modules don't depend on
/// each other, so the scale is duplicated rather than shared. Keep the shared names in step.
enum OverlayType {

    // MARK: - Base scale

    static let hero = Font.custom("Fraunces", size: 46).weight(.semibold).monospacedDigit()
    static let title = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 15, weight: .medium, design: .rounded)
    static let row = Font.system(size: 15, weight: .medium, design: .rounded)
    static let caption = Font.system(size: 13, weight: .medium, design: .rounded)
    static let footnote = Font.system(size: 12, weight: .medium, design: .rounded)

    // MARK: - Break screen

    /// "Relax those eyes" — the largest words in the app.
    static let breakTitle = Font.custom("Fraunces", size: 54).weight(.medium)
    /// The line under it. Regular weight: at 20 pt, medium starts to shout.
    static let breakSubtitle = Font.system(size: 20, weight: .regular, design: .rounded)
    /// The countdown on the screen you were looking at.
    static let breakCountdown = Font.custom("Fraunces", size: 96).weight(.light).monospacedDigit()
    /// The dimmed countdown on every other screen.
    static let quietCountdown = Font.custom("Fraunces", size: 64).weight(.light).monospacedDigit()
    /// Time of day, top-left of the break screen.
    static let clock = Font.system(size: 15, weight: .medium, design: .rounded).monospacedDigit()
    /// "Press [Esc] twice to skip".
    static let hint = Font.system(size: 12.5, weight: .medium, design: .rounded)
    /// The Esc keycap itself.
    static let keycap = Font.system(size: 12.5, weight: .semibold, design: .rounded)
    /// The single word on a wellness nudge: "Blink", "Sit up".
    static let nudge = Font.system(size: 20, weight: .medium, design: .rounded)

    // MARK: - Pre-break card

    /// The all-caps label above the pre-break countdown.
    static let eyebrow = Font.system(size: 11, weight: .semibold, design: .rounded)
    /// The pre-break card's countdown.
    static let cardCountdown = Font.custom("Fraunces", size: 34).weight(.semibold).monospacedDigit()

    // MARK: - Small surfaces

    /// The pill that follows the pointer through the last ten seconds.
    static let cursorPill = Font.system(size: 13, weight: .semibold, design: .rounded)
    /// A toast's one line.
    static let toast = Font.system(size: 13.5, weight: .medium, design: .rounded)

    // MARK: - Opacity

    /// Text on glass never drops below this — under ~0.6 white on a bright wallpaper vanishes.
    static let secondaryOpacity: Double = 0.72
    /// The dimmest text is still legible; used for eyebrows and hints.
    static let tertiaryOpacity: Double = 0.62
}
