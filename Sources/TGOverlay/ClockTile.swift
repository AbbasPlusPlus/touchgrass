// TGOverlay — the animated clock tile on the pre-break card.
// A matcha→pollen rounded square with a dotted clock face whose hand sweeps continuously,
// completing one revolution over the pre-break countdown. The hand interpolates against the
// wall clock at 30 fps, so it glides instead of ticking once a second. Frozen under Reduce Motion.

import SwiftUI

struct ClockTile: View {
    /// When the break arrives, and how long the whole countdown is.
    var deadline: Date
    var total: TimeInterval

    private func progress(at now: Date) -> Double {
        guard total > 0 else { return 0 }
        let remaining = max(0, deadline.timeIntervalSince(now))
        return min(1, max(0, 1 - remaining / total))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(colors: [OverlayPalette.matcha, OverlayPalette.pollen],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: .black.opacity(0.20), radius: 4, y: 1)
            if OverlayMotion.reduceMotion {
                face(progress: 0.6)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    face(progress: progress(at: context.date))
                }
            }
        }
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
    }

    private func face(progress: Double) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width * 0.34

            // Hour dots
            for hour in 0..<12 {
                let angle = Double(hour) / 12 * 2 * .pi - .pi / 2
                let p = CGPoint(x: center.x + cos(angle) * radius,
                                y: center.y + sin(angle) * radius)
                let dot = CGRect(x: p.x - 1.3, y: p.y - 1.3, width: 2.6, height: 2.6)
                context.fill(Path(ellipseIn: dot), with: .color(OverlayPalette.onMatcha.opacity(0.85)))
            }

            // Sweeping hand
            let sweep = progress * 2 * .pi - .pi / 2
            var hand = Path()
            hand.move(to: center)
            hand.addLine(to: CGPoint(x: center.x + cos(sweep) * radius * 0.72,
                                     y: center.y + sin(sweep) * radius * 0.72))
            context.stroke(hand, with: .color(OverlayPalette.onMatcha),
                           style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        }
    }
}
