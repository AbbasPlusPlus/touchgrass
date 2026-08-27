// TGOverlay — a user-defined reminder ("Drink water", "Stretch"): one symbol, one line of text.
// Same size and lifetime as the posture nudge, so custom reminders never feel like a second class.

import SwiftUI

struct CustomNudgeView: View {
    static let size = CGSize(width: 320, height: 200)
    /// SF Symbol name; the view falls back to a generic glyph if the system doesn't know it.
    let symbol: String
    let title: String

    @State private var appeared = false
    @State private var breathe = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.10), .clear],
                                         center: .center, startRadius: 4, endRadius: 62))
                    .frame(width: 124, height: 124)

                Image(systemName: symbol)
                    .font(.system(size: 46, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.92))
                    .scaleEffect(breathe ? 1.06 : 1)
            }
            .frame(height: 108)

            Text(title)
                .font(OverlayType.nudge)
                .foregroundStyle(.white.opacity(0.92))
                .kerning(0.4)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 26)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .glassSurface(RoundedRectangle(cornerRadius: 28, style: .continuous), shadowRadius: 30, shadowY: 12)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.94)
        .animation(OverlayMotion.softSpring(response: 0.5, damping: 0.85), value: appeared)
        .onAppear {
            appeared = true
            guard !OverlayMotion.reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}
