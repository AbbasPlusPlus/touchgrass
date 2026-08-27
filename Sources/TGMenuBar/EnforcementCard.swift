// TGMenuBar — one of the three break-enforcement preview cards.
import SwiftUI
import TGCore

/// A gradient thumbnail of the break screen with a mock Skip control, so the choice is made
/// by looking at the consequence rather than by reading a radio button label.
struct EnforcementCard: View {

    let enforcement: Enforcement
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                thumbnail
                VStack(alignment: .leading, spacing: 1) {
                    Text(enforcement.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(enforcement.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.10),
                                  lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(enforcement.title). \(enforcement.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Mock break screen

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(PresetPalette.gradient(gradientColors))

            VStack(spacing: 3) {
                Text("Relax those eyes")
                    .font(.system(size: 6, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Text("00:30")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    skipChip
                }
            }
            .padding(5)
        }
        .frame(height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// The whole point of the card: what the Skip button looks like in this mode.
    @ViewBuilder
    private var skipChip: some View {
        switch enforcement {
        case .casual:
            // Live and clickable from the first second.
            chip(glyph: "»", background: .white.opacity(0.92), foreground: .black.opacity(0.75))

        case .balanced:
            // Waiting out a countdown ring before it unlocks.
            chip(glyph: "⏱", background: .white.opacity(0.35), foreground: .white)
                .overlay(
                    Circle()
                        .trim(from: 0, to: 0.68)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 15, height: 15)
                )

        case .hardcore:
            // Not offered at all.
            chip(glyph: "⊘", background: .white.opacity(0.10), foreground: .white.opacity(0.35))
        }
    }

    private func chip(glyph: String, background: Color, foreground: Color) -> some View {
        Text(glyph)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: 18, height: 11)
            .background(Capsule().fill(background))
    }

    private var gradientColors: [Color] {
        switch enforcement {
        case .casual:   return PresetPalette.colors(.forest)
        case .balanced: return PresetPalette.colors(.ocean)
        case .hardcore: return PresetPalette.colors(.ember)
        }
    }
}
