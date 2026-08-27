// TGOverlay — the blink reminder: an eye that closes and opens twice, then goes away.
// No text beyond one word; nobody should have to read a nudge.

import SwiftUI

struct BlinkNudgeView: View {
    static let size = CGSize(width: 260, height: 260)

    @State private var openness: CGFloat = 1
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.10), .clear],
                                         center: .center, startRadius: 4, endRadius: 78))
                    .frame(width: 156, height: 156)

                EyeShape(openness: openness)
                    .stroke(Color.white.opacity(0.88),
                            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 128, height: 72)

                Circle()
                    .fill(Color.white.opacity(0.80))
                    .frame(width: 25, height: 25)
                    .scaleEffect(y: max(0.02, openness), anchor: .center)
                    .opacity(Double(min(1, openness * 2.4)))
            }
            .frame(height: 156)

            Text("Blink")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .kerning(0.4)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .glassSurface(RoundedRectangle(cornerRadius: 30, style: .continuous), shadowRadius: 30, shadowY: 12)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.94)
        .animation(OverlayMotion.softSpring(response: 0.5, damping: 0.85), value: appeared)
        .onAppear {
            appeared = true
            guard !OverlayMotion.reduceMotion else { return }
            Task { await blinkTwice() }
        }
    }

    private func blinkTwice() async {
        try? await Task.sleep(nanoseconds: 350_000_000)
        for _ in 0..<2 {
            withAnimation(.easeInOut(duration: 0.30)) { openness = 0.04 }
            try? await Task.sleep(nanoseconds: 330_000_000)
            withAnimation(.easeOut(duration: 0.38)) { openness = 1 }
            try? await Task.sleep(nanoseconds: 560_000_000)
        }
    }
}

/// Two mirrored quadratic curves. `openness` 1 = wide, 0 = a closed line.
private struct EyeShape: Shape {
    var openness: CGFloat

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let lift = rect.height / 2 * max(0.015, openness)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                          control: CGPoint(x: rect.midX, y: rect.midY - lift * 2))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                          control: CGPoint(x: rect.midX, y: rect.midY + lift * 2))
        return path
    }
}
