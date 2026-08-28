// TGMenuBar — the type scale.
import AppKit
import SwiftUI

/// One place for every size and weight the menu bar surfaces use.
///
/// Everything is SF Rounded: at the sizes this app works in — a countdown you read from a metre
/// away, a row you glance at for a quarter of a second — rounded is measurably friendlier and
/// reads a touch larger at the same point size. Sizes are deliberately generous; a break
/// reminder that makes you lean in has already failed.
///
/// `TGOverlay` keeps its own copy (`OverlayType`) with the same base names, because the two
/// modules don't depend on each other. Keep the shared names in step.
enum TGType {

    // MARK: - Scale

    /// The one big number: the quick panel countdown.
    static let hero = Font.custom("Fraunces", size: 48).weight(.semibold).monospacedDigit()
    /// Onboarding's per-step heading.
    static let display = Font.custom("Fraunces", size: 30).weight(.semibold)
    /// The app's own name, on the About page.
    static let heading = Font.custom("Fraunces", size: 22).weight(.semibold)
    /// Card and page headings, and the panel's "no countdown" fallback line.
    static let title = Font.system(size: 17, weight: .semibold, design: .rounded)
    /// Running prose — onboarding copy, the panel's "Break starts in".
    static let body = Font.system(size: 15, weight: .medium, design: .rounded)
    /// A line of an inset list. Same size as `body`; named apart so rows can move on their own.
    static let row = Font.system(size: 15, weight: .medium, design: .rounded)
    /// The emphasised half of a row's value ("**Short** · 1 min").
    static let rowEmphasis = Font.system(size: 15, weight: .semibold, design: .rounded)
    /// Capsule buttons — the action row, the preset chips.
    static let pill = Font.system(size: 14.5, weight: .semibold, design: .rounded)
    /// The quieter tier of capsule button.
    static let pillQuiet = Font.system(size: 14.5, weight: .medium, design: .rounded)
    /// Subheads, chips, and secondary labels.
    static let caption = Font.system(size: 13, weight: .medium, design: .rounded)
    /// The floor. Nothing in this app is smaller than 12 pt except decorative mock-ups.
    static let footnote = Font.system(size: 12, weight: .medium, design: .rounded)

    // MARK: - Ledger (the quick panel's Now tab)

    /// The one thing you open the panel to read: the countdown, set like a page number.
    /// Fraunces rather than SF because at this size the serif is the whole composition —
    /// tabular figures so the digits don't shuffle as the seconds tick.
    static let ledgerTime = Font.custom("Fraunces", size: 64).monospacedDigit()
    /// Stands in for the time when there is nothing to count down ("Call detected on Zoom").
    /// Italic, and much smaller: it's a sentence, not a number.
    ///
    /// We bundle the roman Fraunces only, so `.italic()` has nothing to switch to and quietly
    /// does nothing. Shear the font matrix instead — a 10° oblique, which is what the italic
    /// of a serif this soft looks like anyway at one line and 28 pt.
    static let ledgerReason: Font = obliqueSerif(size: 28, degrees: 10)
    /// The uppercase line above the time. Pair with `.tracking(TGType.eyebrowTracking)`.
    static let eyebrow = Font.system(size: 12, weight: .heavy, design: .rounded)
    /// 0.14em at 12 pt — wide enough that eight caps read as a label rather than a word.
    static let eyebrowTracking: CGFloat = 1.68
    /// The Stats tab's one number — the rest ratio. The same serif as the countdown, at the
    /// size a figure reads as a headline rather than as a display.
    static let statNumber = Font.custom("Fraunces", size: 36).monospacedDigit()
    /// The quiet half of a fact ("Focused").
    static let factLabel = Font.system(size: 13.5, weight: .medium, design: .rounded)
    /// The half you actually read ("8 mins").
    static let factValue = Font.system(size: 15, weight: .semibold, design: .rounded)

    // MARK: - Metrics

    /// Minimum height of an inset-list row, so a 15 pt label has room to breathe.
    static let rowHeight: CGFloat = 44

    // MARK: - Opacity

    /// Secondary text never drops below this — below ~0.6 it stops being readable on glass.
    static let secondaryOpacity: Double = 0.72

    // MARK: - Plumbing

    /// Fraunces at `size`, sheared by `degrees`. Falls back to the system serif italic if the
    /// bundled font hasn't been registered (the demo binaries that skip `TGAssets`).
    private static func obliqueSerif(size: CGFloat, degrees: Double) -> Font {
        let fallback = Font.system(size: size, design: .serif).italic()
        guard NSFont(name: "Fraunces", size: size) != nil else { return fallback }
        // The font matrix carries the point size as well as the shear, so bake both in and
        // ask for size 0 — "use the matrix".
        let slant = CGFloat(tan(degrees * .pi / 180))
        let matrix = AffineTransform(m11: size, m12: 0, m21: size * slant, m22: size, tX: 0, tY: 0)
        let descriptor = NSFontDescriptor(fontAttributes: [.name: "Fraunces", .matrix: matrix])
        guard let font = NSFont(descriptor: descriptor, size: 0) else { return fallback }
        return Font(font)
    }
}
