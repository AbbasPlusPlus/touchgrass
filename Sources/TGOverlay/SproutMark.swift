// TGOverlay — the seedling every wellness nudge is drawn from.
//
// Authored as SVG in a 120 × 120 box (the approved nudge mock); the paths below are that
// artwork transcribed point for point, so the two can be diffed by eye. Nothing here animates:
// `SproutPose` supplies the transforms, this file only supplies the shape.

import SwiftUI

enum SproutMark {

    // MARK: - Geometry (120 × 120 box)

    /// The side of the box the paths were authored in.
    static let box: CGFloat = 120
    /// Where the leaves meet the stem. Leaves fold, perk and rustle about this point.
    static let join = CGPoint(x: 60, y: 78)
    /// The foot of the stem. The whole plant leans and stretches about this point.
    static let base = CGPoint(x: 60, y: 110)
    /// The droplet's resting centre — 4 units above the join, so it lands *on* the join.
    static let dropletCentre = CGPoint(x: 60, y: 74)
    /// Stroke width of the stem, in box units.
    static let stemWidth: CGFloat = 7

    /// A box-space point as a `UnitPoint`, for `rotationEffect(anchor:)` / `scaleEffect(anchor:)`.
    static func anchor(_ point: CGPoint) -> UnitPoint {
        UnitPoint(x: point.x / box, y: point.y / box)
    }

    /// How many points one box unit is worth, when the mark is drawn at `size`.
    static func unit(for size: CGFloat) -> CGFloat { size / box }

    // MARK: - Colours

    // Fixed values rather than palette tokens: these are the brand's greens, and a seedling
    // that changed colour with the system appearance would stop being the same plant. Only the
    // word beside it follows light/dark.

    static let stem = Color.tg(0x8BA579)
    static let leafLeft = Color.tg(0xA6C84D)
    static let leafRight = Color.tg(0x78AF43)
    static let droplet = Color.tg(0xCFE3EE)
}

// MARK: - Shape

/// One piece of the sprout, drawn to fill whatever square it is given.
struct SproutShape: Shape {

    enum Part { case stem, leftLeaf, rightLeaf, droplet }

    let part: Part

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch part {
        case .stem:
            // M60 110 Q60 90 60 78 — straight, but kept as the authored quad curve.
            path.move(to: CGPoint(x: 60, y: 110))
            path.addQuadCurve(to: CGPoint(x: 60, y: 78), control: CGPoint(x: 60, y: 90))
        case .leftLeaf:
            // M60 78 Q30 72 26 48 Q52 50 60 78 Z
            path.move(to: CGPoint(x: 60, y: 78))
            path.addQuadCurve(to: CGPoint(x: 26, y: 48), control: CGPoint(x: 30, y: 72))
            path.addQuadCurve(to: CGPoint(x: 60, y: 78), control: CGPoint(x: 52, y: 50))
            path.closeSubpath()
        case .rightLeaf:
            // M60 78 Q90 72 94 48 Q68 50 60 78 Z
            path.move(to: CGPoint(x: 60, y: 78))
            path.addQuadCurve(to: CGPoint(x: 94, y: 48), control: CGPoint(x: 90, y: 72))
            path.addQuadCurve(to: CGPoint(x: 60, y: 78), control: CGPoint(x: 68, y: 50))
            path.closeSubpath()
        case .droplet:
            path.addEllipse(in: CGRect(x: SproutMark.dropletCentre.x - 4.5,
                                       y: SproutMark.dropletCentre.y - 6.5,
                                       width: 9, height: 13))
        }
        let scale = min(rect.width, rect.height) / SproutMark.box
        return path.applying(CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}
