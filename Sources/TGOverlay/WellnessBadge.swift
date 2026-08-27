// TGOverlay — the shape every wellness nudge takes: one circular badge, nothing else.
import SwiftUI

/// A heavy ink ring around a warm matcha→pollen disc, with one dark glyph in the middle.
///
/// No panel, no glass, no caption. A nudge you have to *read* has already cost more attention
/// than it was worth — the whole thing is one silent shape that appears near the centre of the
/// screen, drifts up a few points, and goes away.
struct WellnessBadge<Glyph: View>: View {

    /// Outer diameter. Everything else is a fraction of it.
    static var diameter: CGFloat { 170 }
    /// Frame the controller sizes its panel to.
    static var size: CGSize { CGSize(width: diameter, height: diameter) }

    /// How long the badge is on screen, so the float can be paced against it.
    var lifetime: TimeInterval
    @ViewBuilder var glyph: () -> Glyph

    @State private var appeared = false
    @State private var floated = false

    private var ring: CGFloat { Self.diameter * 0.058 }      // ≈ 10 pt

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: OverlayPalette.badgeDisc,
                                     startPoint: .bottomLeading, endPoint: .topTrailing))
            glyph()
                .frame(width: Self.diameter * 0.46, height: Self.diameter * 0.46)
        }
        .frame(width: Self.diameter - ring, height: Self.diameter - ring)
        .overlay(
            Circle().strokeBorder(OverlayPalette.badgeRing, lineWidth: ring)
        )
        .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
        .scaleEffect(appeared ? 1 : 0.6)
        .opacity(appeared ? 1 : 0)
        .offset(y: floated ? -6 : 0)
        .onAppear {
            withAnimation(OverlayMotion.softSpring(response: 0.46, damping: 0.74)) { appeared = true }
            guard !OverlayMotion.reduceMotion else { return }
            withAnimation(.easeOut(duration: lifetime)) { floated = true }
        }
        .accessibilityHidden(true)
    }
}
