// TGMenuBar — the TouchGrass mark, parsed once and mapped into whatever rect wants it.
import AppKit
import CoreGraphics

/// The approved logo, `Support/logo/touchgrass-mark.svg`: 46 flat paths that build a disc of
/// grass blades with proper overlap shading. The path data is generated into `LogoMarkData`
/// by `Support/logo/svg2swift.py`; `SVGPathParser` turns it into `CGPath`s, once, lazily.
///
/// Three places draw this mark and none of them can share code with the others, so the data
/// and the parser are copied: `TGOverlay.LogoMarkGeometry` (the cursor pill's badge) and
/// `Support/icon/generate.swift` (the app icon, a standalone script that re-reads the SVG).
enum LogoMarkGeometry {

    /// The SVG's viewBox, in its own coordinates (y down).
    static var viewBox: CGRect { LogoMarkData.viewBox }

    /// One shape ready to draw: already mapped into the destination rect.
    struct Piece {
        let path: CGPath
        let color: CGColor
    }

    // MARK: - Fit

    /// How the artwork is laid into a destination rect.
    enum Fit {
        /// The whole viewBox fits the rect, artwork centred inside it. Matches how a browser
        /// would render the file.
        case viewBox
        /// The artwork's own bounds fill the rect, inset by a fraction of the side. What every
        /// small rendering wants: at 18 pt there is no room to spend anything on air.
        case disc(inset: CGFloat)
    }

    /// Scale and offset taking viewBox coordinates into `rect`. `flipped` is for AppKit's
    /// bottom-left origin, where the SVG's y has to be turned upside down.
    static func transform(in rect: CGRect, flipped: Bool, fit: Fit) -> CGAffineTransform {
        let side = min(rect.width, rect.height)
        let source: CGRect
        let padding: CGFloat
        switch fit {
        case .viewBox:
            source = viewBox
            padding = 0
        case .disc(let insetFraction):
            source = artworkBounds
            padding = side * insetFraction
        }
        guard source.width > 0, source.height > 0 else { return .identity }

        let scale = max(0, side - padding * 2) / max(source.width, source.height)
        let tx = rect.midX - source.midX * scale
        // Flipping mirrors about the viewBox, then the whole thing is centred as usual.
        let ty = flipped ? rect.midY + source.midY * scale : rect.midY - source.midY * scale
        return CGAffineTransform(a: scale, b: 0, c: 0, d: flipped ? -scale : scale, tx: tx, ty: ty)
    }

    // MARK: - Pieces

    /// Below this many points the hairline overlap slivers are sub-pixel: drawing them only
    /// dirties the edges they sit on, so they are dropped and the mass underneath shows.
    static let sliverFloor: CGFloat = 24

    /// The mark's shapes, back to front, mapped into `rect`.
    static func pieces(in rect: CGRect, flipped: Bool, fit: Fit = .disc(inset: 0.02)) -> [Piece] {
        var matrix = transform(in: rect, flipped: flipped, fit: fit)
        let dropSlivers = min(rect.width, rect.height) < sliverFloor
        return parsed.compactMap { shape in
            if dropSlivers && shape.isSliver { return nil }
            guard let path = shape.path.copy(using: &matrix) else { return nil }
            return Piece(path: path, color: shape.color)
        }
    }

    // MARK: - Rendering

    /// Draws the mark into the current AppKit graphics context.
    static func draw(in rect: CGRect, alpha: CGFloat = 1, fit: Fit = .disc(inset: 0.02)) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.setShouldAntialias(true)
        for piece in pieces(in: rect, flipped: true, fit: fit) {
            ctx.addPath(piece.path)
            ctx.setFillColor(piece.color)
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

    // MARK: - Parsing (once)

    private struct ParsedShape {
        let path: CGPath
        let color: CGColor
        /// A hairline seam-filler: smaller than this fraction of the viewBox in both axes.
        let isSliver: Bool
    }

    private static let sliverFraction: CGFloat = 0.05

    private static let parsed: [ParsedShape] = {
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        let limit = max(viewBox.width, viewBox.height) * sliverFraction
        return LogoMarkData.shapes.compactMap { shape in
            guard let path = SVGPathParser.parse(shape.d) else { return nil }
            let components: [CGFloat] = [shape.fill.r, shape.fill.g, shape.fill.b, 1]
            let color = space.flatMap { CGColor(colorSpace: $0, components: components) }
                ?? CGColor(red: shape.fill.r, green: shape.fill.g, blue: shape.fill.b, alpha: 1)
            let box = path.boundingBoxOfPath
            return ParsedShape(path: path, color: color,
                               isSliver: box.width < limit && box.height < limit)
        }
    }()

    /// The union of every shape's bounds — the artwork's true extent, which is a little
    /// smaller than the viewBox.
    private static let artworkBounds: CGRect = {
        parsed.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
    }()
}
