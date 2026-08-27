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

    /// One shape ready to draw: already mapped into the destination rect.
    struct Piece {
        let path: CGPath
        let color: CGColor
    }

    /// How much of the destination rect is left as air, as a fraction of its side. The mark
    /// is a disc with blade tips reaching past it, so it wants almost none — at 18 pt there is
    /// nothing to spare.
    static let defaultInset: CGFloat = 0.02

    // MARK: - Mapping

    /// Scales and centres the artwork's own bounds — not the viewBox, which has a little slack
    /// around the drawing — into `rect`. `flipped` is for AppKit's bottom-left origin, where
    /// the SVG's y has to be turned upside down.
    static func transform(in rect: CGRect, flipped: Bool, inset: CGFloat) -> CGAffineTransform {
        let source = artworkBounds
        guard source.width > 0, source.height > 0 else { return .identity }

        let padding = min(rect.width, rect.height) * inset
        let scale = max(0, min(rect.width, rect.height) - padding * 2) / max(source.width, source.height)
        let tx = rect.midX - source.midX * scale
        // Flipping mirrors the artwork, then the whole thing is centred as usual.
        let ty = flipped ? rect.midY + source.midY * scale : rect.midY - source.midY * scale
        return CGAffineTransform(a: scale, b: 0, c: 0, d: flipped ? -scale : scale, tx: tx, ty: ty)
    }

    // MARK: - Pieces

    /// The mark's shapes, back to front, mapped into `rect`.
    ///
    /// Every shape is drawn at every size. Two thirds of them are hairline seam-fillers that
    /// go sub-pixel below ~24 pt, but measured against a render that omits them the difference
    /// at 18 px is at most 3/255 on 18 of 4704 subpixels — so there is nothing to gain by
    /// simplifying, and the mark stays exactly the SVG at every size.
    static func pieces(in rect: CGRect, flipped: Bool, inset: CGFloat = defaultInset) -> [Piece] {
        var matrix = transform(in: rect, flipped: flipped, inset: inset)
        return parsed.compactMap { shape in
            guard let path = shape.path.copy(using: &matrix) else { return nil }
            return Piece(path: path, color: shape.color)
        }
    }

    // MARK: - Rendering

    /// Draws the mark into the current AppKit graphics context.
    static func draw(in rect: CGRect, alpha: CGFloat = 1, inset: CGFloat = defaultInset) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.setShouldAntialias(true)
        for piece in pieces(in: rect, flipped: true, inset: inset) {
            ctx.addPath(piece.path)
            ctx.setFillColor(piece.color)
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    /// The mark as a full-colour `NSImage`, sized in points (Retina comes free — `NSImage`
    /// re-runs the block per backing scale).
    /// Monochrome silhouette for the status bar: every path filled in black, `isTemplate = true`,
    /// so AppKit tints it like every other menu bar extra (white on dark bars, black on light).
    /// The gaps between blades are real negative space in the artwork, so the silhouette still
    /// reads as grass rather than a solid disc.
    /// Template tinting respects the alpha channel, so dimming is baked into the fill.
    static func templateImage(size: CGFloat, alpha: CGFloat = 1) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // One combined path, one fill: filling the 46 pieces separately leaves antialiased
            // seams between adjacent shapes when they're all the same colour. (`flipped: true`
            // to match `draw(in:)` — SVG y grows downward, this context grows upward.)
            let combined = CGMutablePath()
            for piece in pieces(in: rect, flipped: true) {
                combined.addPath(piece.path)
            }
            ctx.setFillColor(CGColor(gray: 0, alpha: alpha))
            ctx.addPath(combined)
            ctx.fillPath(using: .winding)
            return true
        }
        img.isTemplate = true
        return img
    }

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
    }

    private static let parsed: [ParsedShape] = {
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        return LogoMarkData.shapes.compactMap { shape in
            guard let path = SVGPathParser.parse(shape.d) else { return nil }
            let components: [CGFloat] = [shape.fill.r, shape.fill.g, shape.fill.b, 1]
            let color = space.flatMap { CGColor(colorSpace: $0, components: components) }
                ?? CGColor(red: shape.fill.r, green: shape.fill.g, blue: shape.fill.b, alpha: 1)
            return ParsedShape(path: path, color: color)
        }
    }()

    /// The union of every shape's bounds — the artwork's true extent.
    private static let artworkBounds: CGRect = {
        parsed.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
    }()
}
