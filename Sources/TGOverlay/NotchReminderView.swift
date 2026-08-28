// TGOverlay — the Dynamic-Island pre-break banner.
// A black card that grows out of the notch (the seed morph), fuses to it (top corners square,
// bottom corners round), and drains a lit outline down its two sides and around the bottom as
// the pre-break window elapses. Snooze uses the `zzz` glyph; Start is the tinted primary.

import SwiftUI
import TGCore

struct NotchReminderView: View {

    @ObservedObject var model: PreBreakCardModel
    let metrics: NotchGeometry.Metrics
    /// Demo-only: draw a stand-in notch so the composition is visible off a real notched display.
    var drawFakeNotch: Bool = false

    // Card geometry, in points.
    static let cardWidth: CGFloat = 468
    static let cardHeight: CGFloat = 132
    static let leftColumn: CGFloat = 150
    static let corner: CGFloat = 26
    static let panelWidth: CGFloat = 548
    static let panelHeight: CGFloat = 244

    private let bannerBlack = Color(red: 0.02, green: 0.024, blue: 0.02)
    private let accent = Color(red: 0.482, green: 0.847, blue: 0.561)   // grass green

    @State private var morph: Double = 0

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            card
                .frame(width: Self.cardWidth, height: Self.cardHeight)
                .padding(.top, metrics.notchHeight)

            if drawFakeNotch { fakeNotch }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { syncMorph(animated: false) }
        .onChange(of: model.presented) { _, _ in syncMorph(animated: true) }
    }

    private func syncMorph(animated: Bool) {
        let target: Double = model.presented ? 1 : 0
        guard animated, !OverlayMotion.reduceMotion else { morph = target; return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { morph = target }
    }

    // MARK: - Card

    private var card: some View {
        let contentOpacity = smoothstep(0.5, 0.9, morph)
        let sx = lerp(metrics.notchWidth / Self.cardWidth, 1, morph)
        let sy = lerp(metrics.notchHeight / Self.cardHeight, 1, morph)

        return ZStack(alignment: .top) {
            // The morphing black body — the "seed" that grows out of the notch.
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: Self.corner,
                                   bottomTrailingRadius: Self.corner, topTrailingRadius: 0,
                                   style: .continuous)
                .fill(bannerBlack)
                .frame(width: Self.cardWidth, height: Self.cardHeight)
                .scaleEffect(x: sx, y: sy, anchor: .top)
                .shadow(color: .black.opacity(0.55), radius: 26, y: 16)

            content.opacity(contentOpacity)
            countdownBorder.opacity(contentOpacity)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
    }

    // MARK: - Content

    private var content: some View {
        HStack(spacing: 0) {
            countdownColumn
                .frame(width: Self.leftColumn)

            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)

            detailColumn
                .padding(.leading, 18)
                .padding(.trailing, 22)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
    }

    private var countdownColumn: some View {
        VStack(spacing: 3) {
            Text("Break in")
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .kerning(1.0)
                .foregroundStyle(OverlayPalette.matchaOnDark)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.mmss(max(0, model.deadline.timeIntervalSince(context.date))))
            }
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(OverlayPalette.inkOnDark)
            .contentTransition(.numericText(countsDown: true))
        }
    }

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(model.copy.isEmpty ? model.subtitle : model.copy)
                .font(.system(size: 14))
                .foregroundStyle(OverlayPalette.ink2OnDark)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                if model.snoozesRemaining > 0 {
                    snooze("1m", 60)
                    snooze("5m", 5 * 60)
                    snooze("15m", 15 * 60)
                }
                Spacer(minLength: 4)
                Button(action: model.onStart) {
                    Text("Start").lineLimit(1).fixedSize()
                }
                .buttonStyle(NotchPillStyle(primary: true))
            }
        }
    }

    private func snooze(_ label: String, _ seconds: TimeInterval) -> some View {
        Button(action: { model.onSnooze(seconds) }) {
            HStack(spacing: 4) {
                Image(systemName: "zzz").font(.system(size: 10, weight: .bold))
                Text(label).fixedSize()
            }
        }
        .buttonStyle(NotchPillStyle())
    }

    // MARK: - Countdown border

    private var countdownBorder: some View {
        TimelineView(.animation) { context in
            let frac = fraction(at: context.date)
            let gradient = LinearGradient(colors: [OverlayPalette.pollen, accent],
                                          startPoint: .top, endPoint: .bottom)
            ZStack {
                // faint always-on track
                NotchBorderShape(side: .leading, cornerRadius: Self.corner)
                    .stroke(Color.white.opacity(0.09), style: stroke)
                NotchBorderShape(side: .trailing, cornerRadius: Self.corner)
                    .stroke(Color.white.opacity(0.09), style: stroke)
                // lit portion, receding from the top corners toward the bottom centre
                NotchBorderShape(side: .leading, cornerRadius: Self.corner)
                    .trim(from: 1 - frac, to: 1)
                    .stroke(gradient, style: stroke)
                    .shadow(color: accent.opacity(0.5), radius: 4)
                NotchBorderShape(side: .trailing, cornerRadius: Self.corner)
                    .trim(from: 1 - frac, to: 1)
                    .stroke(gradient, style: stroke)
                    .shadow(color: accent.opacity(0.5), radius: 4)
            }
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
    }

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: 3.5, lineCap: .round) }

    private func fraction(at date: Date) -> Double {
        let total = Double(max(1, model.totalSeconds))
        let remaining = max(0, model.deadline.timeIntervalSince(date))
        return min(1, max(0, remaining / total))
    }

    // MARK: - Fake notch (demo only)

    private var fakeNotch: some View {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 13,
                               bottomTrailingRadius: 13, topTrailingRadius: 0, style: .continuous)
            .fill(bannerBlack)
            .frame(width: metrics.notchWidth, height: metrics.notchHeight)
    }

    // MARK: - Helpers

    private static func mmss(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}
