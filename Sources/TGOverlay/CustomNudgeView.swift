// TGOverlay — a user-defined reminder ("Drink water", "Stretch"): the same badge, their symbol.
import SwiftUI

/// Identical in shape and lifetime to the built-in nudges, so a custom reminder never feels
/// like a second class. The title is a tooltip for the accessibility layer only — the badge
/// itself stays wordless, like the others.
struct CustomNudgeView: View {
    static let size = WellnessBadge<EmptyView>.size

    /// SF Symbol name; SwiftUI falls back to an empty glyph if the system doesn't know it.
    let symbol: String
    let title: String
    var lifetime: TimeInterval = 3.6

    @State private var breathe = false

    var body: some View {
        WellnessBadge(lifetime: lifetime) {
            Image(systemName: symbol)
                .font(.system(size: WellnessBadge<EmptyView>.diameter * 0.30, weight: .medium))
                .foregroundStyle(OverlayPalette.badgeRing)
                .scaleEffect(breathe ? 1.06 : 1)
        }
        .onAppear {
            guard !OverlayMotion.reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityElement()
        .accessibilityLabel(title)
    }
}
