// TGMenuBar — the type scale.
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
    static let display = Font.system(size: 28, weight: .bold, design: .rounded)
    /// The app's own name, on the About page.
    static let heading = Font.system(size: 22, weight: .semibold, design: .rounded)
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

    // MARK: - Metrics

    /// Minimum height of an inset-list row, so a 15 pt label has room to breathe.
    static let rowHeight: CGFloat = 44

    // MARK: - Opacity

    /// Secondary text never drops below this — below ~0.6 it stops being readable on glass.
    static let secondaryOpacity: Double = 0.72
}
