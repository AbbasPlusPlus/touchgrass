// TGOverlay — a whisper next to the pointer: "Starting break in 5".
//
// Fixed dark chrome, not the paper/system pair the rest of the app follows: this capsule
// floats over arbitrary content — a white document, a photo, a terminal — a few centimetres
// from where the eye already is. Dark glass with bone type is the one treatment that stays
// legible over all of it, and it is what the reference build does.

import SwiftUI

struct CursorPillView: View {
    @ObservedObject var model: CursorPillModel

    static let size = CGSize(width: 236, height: 36)
    static let inset: CGFloat = 14       // shadow room inside the panel

    private static let corner: CGFloat = 12

    var body: some View {
        HStack(spacing: 9) {
            LogoBadge(side: 24)
            Text(model.text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(OverlayPalette.inkOnDark)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(chrome)
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Self.inset)
        .opacity(model.presented ? 1 : 0)
        .scaleEffect(model.presented ? 1 : 0.94, anchor: .topLeading)
        .animation(OverlayMotion.ease(0.28), value: model.presented)
    }

    /// A dark, softly-cornered capsule: glass where we can have it, flat ink paper otherwise.
    @ViewBuilder
    private var chrome: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        Group {
            if LiquidGlass.isUsable {
                shape
                    .fill(Color.tg(OverlayPalette.Hex.paperDark, opacity: 0.62))
                    .liquidGlass(in: shape)
            } else {
                shape.fill(Color.tg(OverlayPalette.Hex.paperDark, opacity: 0.98))
            }
        }
        .overlay(shape.strokeBorder(Color.tg(OverlayPalette.Hex.inkDark, opacity: 0.16), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.30), radius: 8, y: 3)
        .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
    }
}
