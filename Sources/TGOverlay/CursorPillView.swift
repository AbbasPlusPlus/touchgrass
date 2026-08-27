// TGOverlay — a whisper next to the pointer: "Short break in 5".

import SwiftUI

struct CursorPillView: View {
    @ObservedObject var model: CursorPillModel

    static let size = CGSize(width: 210, height: 34)
    static let inset: CGFloat = 12       // shadow room inside the panel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: model.symbol)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
            Text(model.text)
                .font(OverlayType.cursorPill)
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .glassSurface(Capsule(), shadowRadius: 10, shadowY: 3)
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Self.inset)
        .opacity(model.presented ? 1 : 0)
        .scaleEffect(model.presented ? 1 : 0.94, anchor: .topLeading)
        .animation(OverlayMotion.ease(0.28), value: model.presented)
    }
}
