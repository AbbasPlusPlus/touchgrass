// TGOverlay — the TouchGrass mark's raw path data.
import AppKit
import CoreGraphics

/// The approved logo from `Support/logo/touchgrass-mark.svg`: five flat blades clipped to a
/// disc. The coordinates below are the SVG's, verbatim, in its 512×512 viewBox.
///
/// A verbatim copy of `TGMenuBar.LogoMarkGeometry` — the two modules don't depend on each
/// other. `Support/icon/generate.swift` carries the same numbers again for the app icon.
/// If one changes, change all three.
enum LogoMarkGeometry {

    static let viewBox: CGFloat = 512
    static let discCentre = CGPoint(x: 262, y: 268)
    static let discRadius: CGFloat = 192

    /// One drawing instruction, in viewBox coordinates (y down, like the SVG).
    enum Command {
        case move(CGFloat, CGFloat)
        case line(CGFloat, CGFloat)
        /// c1x, c1y, c2x, c2y, x, y
        case curve(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
    }

    struct Blade {
        let hex: UInt32
        /// True for the two thin slits that turn to mush below ~24 px.
        let isSliver: Bool
        let commands: [Command]
    }

    /// Back to front, exactly the SVG's document order.
    static let blades: [Blade] = [
        // 1 · big light crescent along the left rim
        Blade(hex: 0xA6C84D, isSliver: false, commands: [
            .move(348, 82),
            .curve(220, 96, 72, 180, 72, 300),
            .curve(72, 400, 180, 462, 285, 462),
            .curve(205, 428, 163, 345, 180, 258),
            .curve(197, 170, 270, 112, 348, 82),
        ]),
        // 2 · second blade, fat, base flows to bottom
        Blade(hex: 0x78AF43, isSliver: false, commands: [
            .move(408, 150),
            .curve(320, 180, 238, 252, 213, 342),
            .curve(202, 400, 210, 442, 228, 462),
            .line(372, 462),
            .curve(320, 380, 330, 268, 408, 150),
        ]),
        // 3 · third blade, overlapping blade 2's base
        Blade(hex: 0x4F8D3C, isSliver: true, commands: [
            .move(452, 226),
            .curve(368, 252, 296, 314, 268, 384),
            .curve(254, 424, 258, 452, 272, 462),
            .line(400, 462),
            .curve(370, 390, 392, 302, 452, 226),
        ]),
        // 4 · dark bottom mass, spanning the whole base
        Blade(hex: 0x27521F, isSliver: false, commands: [
            .move(462, 302),
            .curve(372, 314, 296, 356, 258, 408),
            .curve(236, 430, 222, 448, 214, 462),
            .line(470, 462),
            .line(470, 302),
            .curve(468, 302, 465, 302, 462, 302),
        ]),
        // 5 · light leaf over the dark mass, belly on the rim
        Blade(hex: 0x93C04C, isSliver: true, commands: [
            .move(288, 456),
            .curve(314, 384, 376, 342, 452, 332),
            .curve(452, 392, 424, 434, 382, 452),
            .curve(350, 464, 314, 464, 288, 456),
        ]),
    ]

    // MARK: - Mapping

    /// How the 512×512 viewBox is laid into a destination rect.
    enum Fit {
        /// The whole viewBox fits the rect — the disc then sits slightly right of centre and
        /// fills about three quarters of it, exactly as the SVG draws it.
        case viewBox
        /// The *disc* fits the rect, inset by a fraction of the side. What every small
        /// rendering wants: at 18 pt there is no room to spend a quarter of the box on air.
        case disc(inset: CGFloat)
    }

    /// Scale and offset taking viewBox coordinates into `rect`. `flipped` is for AppKit's
    /// bottom-left origin, where the SVG's y has to be turned upside down.
    static func mapping(in rect: CGRect, flipped: Bool, fit: Fit) -> (s: CGFloat, dx: CGFloat, dy: CGFloat) {
        let side = min(rect.width, rect.height)
        switch fit {
        case .viewBox:
            let s = side / viewBox
            return (s,
                    rect.minX + (rect.width - side) / 2,
                    rect.minY + (rect.height - side) / 2)
        case .disc(let insetFraction):
            let inset = side * insetFraction
            let s = (side - inset * 2) / (discRadius * 2)
            // Left edge of the disc, and its lowest edge in whichever y direction we're in.
            let minX = discCentre.x - discRadius
            let minY = flipped ? viewBox - (discCentre.y + discRadius) : discCentre.y - discRadius
            return (s,
                    rect.minX + (rect.width - side) / 2 + inset - minX * s,
                    rect.minY + (rect.height - side) / 2 + inset - minY * s)
        }
    }

    // MARK: - Paths

    /// Replays `commands` into a `CGPath` mapped into `rect`.
    static func cgPath(_ commands: [Command], in rect: CGRect, flipped: Bool,
                       fit: Fit = .disc(inset: 0.02)) -> CGPath {
        let (s, dx, dy) = mapping(in: rect, flipped: flipped, fit: fit)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: flipped ? dy + (viewBox - y) * s : dy + y * s)
        }

        let path = CGMutablePath()
        for command in commands {
            switch command {
            case .move(let x, let y):
                path.move(to: point(x, y))
            case .line(let x, let y):
                path.addLine(to: point(x, y))
            case .curve(let c1x, let c1y, let c2x, let c2y, let x, let y):
                path.addCurve(to: point(x, y), control1: point(c1x, c1y), control2: point(c2x, c2y))
            }
        }
        path.closeSubpath()
        return path
    }

    /// The clipping disc, in the same space.
    static func discPath(in rect: CGRect, flipped: Bool, fit: Fit = .disc(inset: 0.02)) -> CGPath {
        let (s, dx, dy) = mapping(in: rect, flipped: flipped, fit: fit)
        let cy = flipped ? viewBox - discCentre.y : discCentre.y
        let box = CGRect(x: dx + (discCentre.x - discRadius) * s,
                         y: dy + (cy - discRadius) * s,
                         width: discRadius * 2 * s,
                         height: discRadius * 2 * s)
        return CGPath(ellipseIn: box, transform: nil)
    }

    // MARK: - Rendering

    /// Below this many points the two thin slits stop reading as separate blades and just
    /// muddy the silhouette, so they are merged into the blade underneath them.
    static let sliverFloor: CGFloat = 26

    /// Draws the mark into the current AppKit graphics context.
    static func draw(in rect: CGRect, alpha: CGFloat = 1, fit: Fit = .disc(inset: 0.02)) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let side = min(rect.width, rect.height)
        let dropSlivers = side < sliverFloor

        ctx.saveGState()
        ctx.addPath(discPath(in: rect, flipped: true, fit: fit))
        ctx.clip()
        for blade in blades {
            // At menu-bar size the slivers are a pixel wide; drawing them in their own hue
            // just dirties the edge, so they inherit the darker mass they sit on.
            let hex = (dropSlivers && blade.isSliver) ? 0x27521F : blade.hex
            ctx.addPath(cgPath(blade.commands, in: rect, flipped: true, fit: fit))
            ctx.setFillColor(NSColor.ovHex(UInt32(hex), alpha: alpha).cgColor)
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    /// The mark as a full-colour `NSImage`, sized in points (Retina comes free — `NSImage`
    /// re-runs the block per backing scale).
    static func image(size: CGFloat, alpha: CGFloat = 1) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect, alpha: alpha)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "TouchGrass"
        return image
    }
}
