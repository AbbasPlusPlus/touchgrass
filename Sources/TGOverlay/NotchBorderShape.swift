// TGOverlay — one half of the countdown outline that traces the banner's exposed borders.
// The top is fused to the notch, so the lit edge runs down one side, around the bottom corner,
// and into the bottom centre. Two mirrored copies, trimmed independently, drain from both top
// corners toward the bottom centre as the pre-break window elapses.

import SwiftUI

struct NotchBorderShape: Shape {

    enum Side { case leading, trailing }

    var side: Side
    /// Inset from the edge so the stroke sits fully inside the rounded body.
    var inset: CGFloat = 1.5
    /// The banner's bottom corner radius.
    var cornerRadius: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        let midX = rect.midX
        let bottom = rect.maxY - inset

        var path = Path()
        switch side {
        case .leading:
            let x = rect.minX + inset
            path.move(to: CGPoint(x: x, y: rect.minY))                 // top-left (at the notch)
            path.addLine(to: CGPoint(x: x, y: bottom - r))             // down the left edge
            path.addQuadCurve(to: CGPoint(x: x + r, y: bottom),        // around the bottom-left curve
                              control: CGPoint(x: x, y: bottom))
            path.addLine(to: CGPoint(x: midX, y: bottom))              // into the bottom centre
        case .trailing:
            let x = rect.maxX - inset
            path.move(to: CGPoint(x: x, y: rect.minY))                 // top-right (at the notch)
            path.addLine(to: CGPoint(x: x, y: bottom - r))             // down the right edge
            path.addQuadCurve(to: CGPoint(x: x - r, y: bottom),        // around the bottom-right curve
                              control: CGPoint(x: x, y: bottom))
            path.addLine(to: CGPoint(x: midX, y: bottom))              // into the bottom centre
        }
        return path
    }
}
