// TGOverlay — the posture reminder: an arrow that rises, once, and settles.
import SwiftUI

struct PostureNudgeView: View {
    static let size = WellnessBadge<EmptyView>.size

    var lifetime: TimeInterval = 3.6

    @State private var risen = false

    var body: some View {
        WellnessBadge(lifetime: lifetime) {
            Image(systemName: "arrow.up")
                .font(.system(size: WellnessBadge<EmptyView>.diameter * 0.34,
                              weight: .semibold, design: .rounded))
                .foregroundStyle(OverlayPalette.badgeRing)
                .offset(y: risen ? -4 : 4)
        }
        .onAppear {
            guard !OverlayMotion.reduceMotion else { risen = true; return }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.62).delay(0.35)) { risen = true }
        }
    }
}
