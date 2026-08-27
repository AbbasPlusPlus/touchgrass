// TGOverlay — the shared chrome for every small floating surface (card, toast, pill, nudge).
// Liquid Glass, a hairline highlight, and a soft drop shadow drawn in SwiftUI rather than by
// the window server (a transparent NSWindow's own shadow is rectangular and ugly).

import SwiftUI

struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var shadowRadius: CGFloat = 24
    var shadowY: CGFloat = 10

    func body(content: Content) -> some View {
        base(content)
            .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.34), radius: shadowRadius, x: 0, y: shadowY)
            .shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: 1)
    }

    @ViewBuilder
    private func base(_ content: Content) -> some View {
        if OverlayMotion.reduceTransparency {
            content.background(Color(white: 0.11).opacity(0.97), in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
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
