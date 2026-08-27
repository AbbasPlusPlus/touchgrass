// TGOverlay — the T-60s card. Top-right, quiet, dismissible, never in the way.
// Compact mode shows only the countdown and one line until the pointer arrives.

import SwiftUI
import TGCore

struct PreBreakCardView: View {
    @ObservedObject var model: PreBreakCardModel

    static let width: CGFloat = 448
    static let maxHeight: CGFloat = 148
    static let margin: CGFloat = 24
    static let inset: CGFloat = 30          // room for the drop shadow inside the panel

    @State private var hovering = false
    @State private var closeHovering = false

    private var expanded: Bool { !model.compact || hovering }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.margin)
            card
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .offset(y: model.presented ? 0 : -(Self.maxHeight + Self.margin + 12))
        .animation(OverlayMotion.softSpring(response: 0.52, damping: 0.82), value: model.presented)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: expanded ? 14 : 0) {
            header
            if expanded {
                actions.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: Self.width, alignment: .leading)
        .overlay(alignment: .topTrailing) { closeButton.padding(12) }
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(OverlayMotion.softSpring(response: 0.42, damping: 0.88), value: expanded)
        .onHover { hovering = $0 }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ClockTile(progress: model.clockProgress)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.eyebrowLine)
                    .font(OverlayType.eyebrow)
                    .textCase(.uppercase)
                    .kerning(0.7)
                    .foregroundStyle(OverlayPalette.matcha)
                    .lineLimit(1)
                Text(model.countdownText)
                    .font(OverlayType.cardCountdown)
                    .foregroundStyle(OverlayPalette.ink)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(OverlayMotion.reduceMotion ? nil : .easeOut(duration: 0.3),
                               value: model.secondsLeft)
                Text(model.copy.isEmpty ? model.subtitle : model.copy)
                    .font(OverlayType.body)
                    .foregroundStyle(OverlayPalette.ink2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 18)
        }
    }

    private var closeButton: some View {
        Button(action: model.onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(OverlayPalette.ink2)
                .frame(width: 18, height: 18)
                .background(Circle().fill(closeHovering ? OverlayPalette.stone : OverlayPalette.stone.opacity(0.45)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(OverlayMotion.ease(0.12)) { closeHovering = hovering }
        }
        .accessibilityLabel("Dismiss")
    }

    // MARK: - Actions

    private var actions: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 8) {
                Button(action: model.onStart) {
                    Text("Start break now").lineLimit(1).fixedSize()
                }
                .buttonStyle(GlassPillStyle(size: .regular, tinted: true))

                Spacer(minLength: 4)

                if model.snoozesRemaining > 0 {
                    snooze("+1m", 60)
                    snooze("+5m", 5 * 60)
                    snooze("+15m", 15 * 60)
                }
            }
        }
    }

    private func snooze(_ label: String, _ seconds: TimeInterval) -> some View {
        Button(action: { model.onSnooze(seconds) }) {
            Text(label).lineLimit(1).fixedSize()
        }
        .buttonStyle(GlassPillStyle(size: .small))
    }
}
