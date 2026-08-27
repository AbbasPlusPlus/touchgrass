// TGMenuBar — the menu bar glyph: the TouchGrass mark itself.
import AppKit

/// The status item's icon.
///
/// Full colour rather than a template: the mark's whole identity is the five greens layered
/// into a disc, and a template image would flatten it into one silhouette. The disc also holds
/// its shape at 18 pt in a way a fan of hairline blades never did — the silhouette is a solid
/// circle, so the only thing that softens at @1x is the shading inside it.
public enum StatusBarIcon {

    /// Nominal point size of the status item glyph.
    public static let size: CGFloat = 18

    // MARK: - Public

    /// - Parameter dimmed: renders at reduced alpha for the paused / stopped states, which
    ///   reads as "not running" against both a light and a dark menu bar.
    public static func grass(dimmed: Bool = false) -> NSImage {
        LogoMarkGeometry.templateImage(size: size, alpha: dimmed ? 0.45 : 1.0)
    }
}
