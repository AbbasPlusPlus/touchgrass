// TGOverlay — the animated clock tile on the pre-break card.
// A warm gradient rounded square with a dotted clock face whose minute hand sweeps in real time,
// completing a revolution over the pre-break minute. Frozen under Reduce Motion.

import SwiftUI

struct ClockTile: View {
    /// 0...1, how far through the pre-break countdown we are (drives the hand).
    var progress: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color(red: 0.98, green: 0.62, blue: 0.30),
                                            Color(red: 0.93, green: 0.34, blue: 0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            face
        }
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
    }

    private var face: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width * 0.34

            // Hour dots
            for hour in 0..<12 {
                let angle = Double(hour) / 12 * 2 * .pi - .pi / 2
                let p = CGPoint(x: center.x + cos(angle) * radius,
                                y: center.y + sin(angle) * radius)
                let dot = CGRect(x: p.x - 1.3, y: p.y - 1.3, width: 2.6, height: 2.6)
                context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.85)))
            }

            // Sweeping hand
            let sweep = (OverlayMotion.reduceMotion ? 0.6 : progress) * 2 * .pi - .pi / 2
            var hand = Path()
            hand.move(to: center)
            hand.addLine(to: CGPoint(x: center.x + cos(sweep) * radius * 0.72,
                                     y: center.y + sin(sweep) * radius * 0.72))
            context.stroke(hand, with: .color(.white), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        }
    }
}
