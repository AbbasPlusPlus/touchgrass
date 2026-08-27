// TGMenuBar — two blades of grass, for the onboarding hero.
import SwiftUI

/// The same two strokes the break screen draws in its corner (`TGOverlay.GrassStrokes`), used
/// here behind the onboarding hero. Static, and almost invisible on purpose.
struct GrassStrokes: View {

    /// Stroke colour, already carrying its opacity.
    var color: Color = TGPalette.matcha.opacity(0.35)
    /// Height of the taller blade.
    var height: CGFloat = 168

    /// The mock-up's viewBox, kept so the curves can be copied across unchanged.
    private static let box = CGSize(width: 90, height: 70)

    var body: some View {
        Canvas { context, size in
            let s = size.height / Self.box.height
            let x = { (v: CGFloat) in v * s }
            let y = { (v: CGFloat) in v * s }

            var tall = Path()
            tall.move(to: CGPoint(x: x(30), y: y(70)))
            tall.addCurve(to: CGPoint(x: x(34), y: y(14)),
                          control1: CGPoint(x: x(36), y: y(46)),
                          control2: CGPoint(x: x(28), y: y(30)))

            var short = Path()
            short.move(to: CGPoint(x: x(48), y: y(70)))
            short.addCurve(to: CGPoint(x: x(51), y: y(26)),
                           control1: CGPoint(x: x(44), y: y(52)),
                           control2: CGPoint(x: x(54), y: y(40)))

            let style = StrokeStyle(lineWidth: 3 * s, lineCap: .round)
            context.stroke(tall, with: .color(color), style: style)
            context.stroke(short, with: .color(color.opacity(0.6)), style: style)
        }
        .frame(width: height * (Self.box.width / Self.box.height), height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
