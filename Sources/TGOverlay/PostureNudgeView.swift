// TGOverlay — the posture reminder: a slouched line that straightens, once, slowly.

import SwiftUI

struct PostureNudgeView: View {
    static let size = CGSize(width: 320, height: 200)

    @State private var slouch: CGFloat = 1
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Seat / ground reference so the straightening reads as "up", not "away".
                Rectangle()
                    .fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.22), .white.opacity(0)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 124, height: 1)
                    .offset(y: 50)

                FigureShape(slouch: slouch)
                    .stroke(Color.white.opacity(0.88),
                            style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 120, height: 96)
                    .offset(y: slouch * 5)
            }
            .frame(height: 108)

            Text("Sit up")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .kerning(0.4)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .glassSurface(RoundedRectangle(cornerRadius: 28, style: .continuous), shadowRadius: 30, shadowY: 12)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.94)
        .animation(OverlayMotion.softSpring(response: 0.5, damping: 0.85), value: appeared)
        .onAppear {
            appeared = true
            guard !OverlayMotion.reduceMotion else { slouch = 0; return }
            Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                withAnimation(.timingCurve(0.3, 0.8, 0.25, 1, duration: 1.9)) { slouch = 0 }
            }
        }
    }
}

/// A head and a spine over a seat line. `slouch` 1 = curled forward, 0 = upright.
private struct FigureShape: Shape {
    var slouch: CGFloat

    var animatableData: CGFloat {
        get { slouch }
        set { slouch = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let s = max(0, min(1, slouch))
        let headRadius = rect.width * 0.13

        let hip = CGPoint(x: rect.midX, y: rect.maxY)
        let neck = CGPoint(x: rect.midX + rect.width * 0.24 * s,
                           y: rect.minY + rect.height * (0.24 + 0.24 * s))
        // Control point bows the spine forward as the figure slumps.
        let control = CGPoint(x: rect.midX + rect.width * 0.20 * s,
                              y: rect.midY + rect.height * 0.14 * s)
        let headCentre = CGPoint(x: neck.x + rect.width * 0.09 * s,
                                 y: neck.y - headRadius * 1.25)

        var path = Path()
        path.move(to: hip)
        path.addQuadCurve(to: neck, control: control)
        path.addEllipse(in: CGRect(x: headCentre.x - headRadius,
                                   y: headCentre.y - headRadius,
                                   width: headRadius * 2,
                                   height: headRadius * 2))
        return path
    }
}
