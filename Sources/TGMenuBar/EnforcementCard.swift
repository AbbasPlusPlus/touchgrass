// TGMenuBar — one of the three break-enforcement preview cards.
import SwiftUI
import TGCore

/// A gradient thumbnail of the break screen with a mock Skip control, so the choice is made
/// by looking at the consequence rather than by reading a radio button label.
struct EnforcementCard: View {

    let enforcement: Enforcement
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                thumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text(enforcement.title)
                        .font(TGType.caption)
                        .foregroundStyle(TGPalette.ink)
                    Text(enforcement.subtitle)
                        .font(TGType.footnote)
                        .foregroundStyle(TGPalette.ink2)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? TGPalette.matcha.opacity(0.14)
                                     : (hovering ? TGPalette.stone.opacity(0.40)
                                                 : TGPalette.paper2.opacity(0.55)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? TGPalette.matcha : TGPalette.stone,
                                  lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: TGPalette.ink.opacity(hovering && !isSelected ? 0.18 : 0),
                    radius: hovering ? 5 : 0, y: hovering ? 1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(TGPalette.hoverAnimation()) { self.hovering = hovering }
        }
        .accessibilityLabel("\(enforcement.title). \(enforcement.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Mock break screen

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(PresetPalette.gradient(gradientColors))

            VStack(spacing: 3) {
                Text("Look away")
                    .font(.system(size: 6, weight: .medium, design: .rounded))
                    .foregroundStyle(thumbnailInk.opacity(0.78))
                Text("00:30")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(thumbnailInk)
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
            chip(glyph: "»", background: .tg(0xFAF7EC, opacity: 0.92), foreground: .tg(0x3D443A))

        case .balanced:
            // Waiting out a countdown ring before it unlocks — and the ring is clay, the one
            // place in the app that colour is allowed.
            chip(glyph: "⏱", background: thumbnailInk.opacity(0.28), foreground: thumbnailInk)
                .overlay(
                    Circle()
                        .trim(from: 0, to: 0.68)
                        .stroke(TGPalette.clay, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 15, height: 15)
                )

        case .hardcore:
            // Not offered at all.
            chip(glyph: "⊘", background: thumbnailInk.opacity(0.10), foreground: thumbnailInk.opacity(0.35))
        }
    }

    private func chip(glyph: String, background: Color, foreground: Color) -> some View {
        Text(glyph)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: 18, height: 11)
            .background(Capsule().fill(background))
    }

    /// A three-step ramp through the palette — paper, matcha, deep — so the thumbnails read
    /// as "how firmly does this insist" before a single word has been read. Fixed hexes
    /// rather than dynamic tokens: a thumbnail of a break screen shouldn't invert with the
    /// system, and the ink on top has to stay predictable.
    private var gradientColors: [Color] {
        switch enforcement {
        case .casual:   return [.tg(0xE9E4D2), .tg(0xD8D2BB)]
        case .balanced: return [.tg(0x6E8560), .tg(0x47563F)]
        case .hardcore: return [.tg(0x2E352B), .tg(0x181C16)]
        }
    }

    private var thumbnailInk: Color {
        enforcement == .casual ? .tg(0x3D443A) : .tg(0xF3F1E2)
    }
}
