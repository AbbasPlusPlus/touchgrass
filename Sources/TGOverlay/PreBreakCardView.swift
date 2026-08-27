// TGOverlay — the T-60s card. Top-right, quiet, dismissible, never in the way.
// Compact mode shows only the countdown and one line until the pointer arrives.

import SwiftUI
import TGCore

struct PreBreakCardView: View {
    @ObservedObject var model: PreBreakCardModel

    static let width: CGFloat = 404
    static let maxHeight: CGFloat = 132
    static let margin: CGFloat = 24
    static let inset: CGFloat = 30          // room for the drop shadow inside the panel

    @State private var hovering = false

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
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: Self.width, alignment: .leading)
        .overlay(alignment: .topTrailing) { closeButton.padding(12) }
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(OverlayMotion.softSpring(response: 0.42, damping: 0.88), value: expanded)
        .onHover { hovering = $0 }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.eyebrow.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .kerning(1.3)
                    .foregroundStyle(.white.opacity(0.52))
                Text(model.countdownText)
                    .font(.system(size: 32, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.95))
            }
            .fixedSize()

            Text(model.copy)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))
                .lineSpacing(2)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 18)
        }
    }

    private var closeButton: some View {
        Button(action: model.onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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
