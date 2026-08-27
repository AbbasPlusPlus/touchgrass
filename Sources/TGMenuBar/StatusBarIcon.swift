// TGMenuBar — the menu bar glyph, drawn in code so there is no asset catalog to ship.
import AppKit

/// Draws TouchGrass's status item glyph: a small fan of grass blades.
/// Always a *template* image so macOS tints it for light/dark menu bars and for
/// the inverted "menu bar item selected" appearance.
public enum StatusBarIcon {

    /// Nominal point size of the status item glyph.
    public static let size: CGFloat = 18

    // MARK: - Public

    /// - Parameter dimmed: renders at reduced alpha for the paused / stopped states.
    ///   Template images tint through their alpha channel, so a translucent template
    ///   reads as a greyed-out glyph in both light and dark menu bars.
    public static func grass(dimmed: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            draw(alpha: dimmed ? 0.42 : 1.0)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "TouchGrass"
        return image
    }

    // MARK: - Drawing

    /// Blade geometry in an 18×18 box, bottom-left origin: where each blade is rooted,
    /// where its tip lands, and how wide it is at the root.
    private static let blades: [(base: CGFloat, tip: CGFloat, top: CGFloat, width: CGFloat)] = [
        (4.4,  1.9, 10.4, 1.9),
        (6.5,  4.4, 14.0, 2.1),
        (9.0,  9.1, 15.9, 2.2),
        (11.5, 13.6, 14.0, 2.1),
        (13.6, 16.1, 10.4, 1.9),
    ]

    private static let baseY: CGFloat = 2.2

    /// Each blade is a filled sliver — wide at the root, tapering to a point — which reads as
    /// grass at 18 pt far better than a uniform stroke does.
    private static func draw(alpha: CGFloat) {
        NSColor.black.withAlphaComponent(alpha).setFill()
        for blade in blades {
            let rise = blade.top - baseY
            let run = blade.tip - blade.base
            let halfWidth = blade.width / 2
            let tip = NSPoint(x: blade.tip, y: blade.top)

            let path = NSBezierPath()
            path.move(to: NSPoint(x: blade.base - halfWidth, y: baseY))
            path.curve(
                to: tip,
                controlPoint1: NSPoint(x: blade.base - halfWidth + run * 0.05, y: baseY + rise * 0.50),
                controlPoint2: NSPoint(x: blade.base - halfWidth + run * 0.50, y: baseY + rise * 0.86)
            )
            path.curve(
                to: NSPoint(x: blade.base + halfWidth, y: baseY),
                controlPoint1: NSPoint(x: blade.base + halfWidth + run * 0.50, y: baseY + rise * 0.86),
                controlPoint2: NSPoint(x: blade.base + halfWidth + run * 0.05, y: baseY + rise * 0.50)
            )
            path.close()
            path.fill()
        }
    }
}
