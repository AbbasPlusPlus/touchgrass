// TGOverlay — the shared chrome for every small floating surface (card, toast, pill, nudge).
// Liquid Glass washed toward paper, a hairline highlight, and a soft drop shadow drawn in
// SwiftUI rather than by the window server (a transparent NSWindow's own shadow is rectangular
// and ugly).

import SwiftUI

struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var shadowRadius: CGFloat = 24
    var shadowY: CGFloat = 10

    func body(content: Content) -> some View {
        base(content)
            .overlay(shape.strokeBorder(OverlayPalette.glassRim, lineWidth: 0.8))
            .shadow(color: .black.opacity(0.28), radius: shadowRadius, x: 0, y: shadowY)
            .shadow(color: .black.opacity(0.14), radius: 3, x: 0, y: 1)
    }

    @ViewBuilder
    private func base(_ content: Content) -> some View {
        if LiquidGlass.isUsable {
            // The wash goes on *before* `.glassEffect`, which puts its material underneath —
            // so the wash lands on top of the glass and tints it toward paper. Without it the
            // material picks up whatever is behind the window and reads gray.
            content
                .background(OverlayPalette.glassWash, in: shape)
                .liquidGlass(in: shape)
        } else {
            // One-for-one swap: flat paper2 where the glass would have been.
            content.background(OverlayPalette.glassFallback, in: shape)
        }
    }
}

extension View {
    func glassSurface<S: InsettableShape>(_ shape: S,
                                shadowRadius: CGFloat = 24,
                                shadowY: CGFloat = 10) -> some View {
        modifier(GlassSurface(shape: shape, shadowRadius: shadowRadius, shadowY: shadowY))
    }
}
