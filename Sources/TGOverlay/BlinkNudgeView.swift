// TGOverlay — the blink reminder: two closed eyes that open, close and open again.
import SwiftUI

struct BlinkNudgeView: View {
    static let size = WellnessBadge<EmptyView>.size

    /// Matches the controller's lifetime for this nudge, so the float finishes as it fades.
    var lifetime: TimeInterval = 2.9

    @State private var openness: CGFloat = 0

    var body: some View {
        WellnessBadge(lifetime: lifetime) {
            EyePair(openness: openness)
                .stroke(OverlayPalette.badgeRing,
                        style: StrokeStyle(lineWidth: WellnessBadge<EmptyView>.diameter * 0.048,
                                           lineCap: .round))
        }
        .onAppear {
            guard !OverlayMotion.reduceMotion else { return }
            Task { await blink() }
        }
    }

    /// Open → close → open, once, over about two and a half seconds.
    private func blink() async {
        try? await Task.sleep(nanoseconds: 380_000_000)
        withAnimation(.easeInOut(duration: 0.55)) { openness = 1 }
        try? await Task.sleep(nanoseconds: 900_000_000)
        withAnimation(.easeInOut(duration: 0.34)) { openness = 0 }
        try? await Task.sleep(nanoseconds: 520_000_000)
        withAnimation(.easeInOut(duration: 0.45)) { openness = 1 }
    }
}

/// Two lids side by side. `openness` 0 = shut (a thick, almost flat mark), 1 = open (a tall
/// arc with clear air under it).
///
/// A stroked arc rather than a filled crescent: at this size a filled lens turns into a wedge
/// the moment the two edges cross, and a round-capped stroke is exactly the mark the reference
/// build draws when the eyes are closed.
struct EyePair: Shape {
    var openness: CGFloat

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let gap = rect.width * 0.14
        let eyeWidth = (rect.width - gap) / 2
        let t = max(0, min(1, openness))
        // Measured against the eye's *width*, not the box: an arc a third as tall as it is
        // wide is an eye; anything taller is a pair of rabbit ears.
        let lift = eyeWidth * (0.05 + 0.28 * t)
        let midY = rect.midY + lift / 2

        var path = Path()
        for index in 0..<2 {
            let minX = rect.minX + CGFloat(index) * (eyeWidth + gap)
            path.move(to: CGPoint(x: minX, y: midY))
            path.addQuadCurve(to: CGPoint(x: minX + eyeWidth, y: midY),
                              control: CGPoint(x: minX + eyeWidth / 2, y: midY - lift * 2))
        }
        return path
    }
}
