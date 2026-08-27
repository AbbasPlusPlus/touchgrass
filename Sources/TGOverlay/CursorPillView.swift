// TGOverlay — a whisper next to the pointer: "Short break in 5".

import SwiftUI

struct CursorPillView: View {
    @ObservedObject var model: CursorPillModel

    static let size = CGSize(width: 176, height: 30)
    static let inset: CGFloat = 12       // shadow room inside the panel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: model.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Text(model.text)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .glassSurface(Capsule(), shadowRadius: 10, shadowY: 3)
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Self.inset)
        .opacity(model.presented ? 1 : 0)
        .scaleEffect(model.presented ? 1 : 0.94, anchor: .topLeading)
        .animation(OverlayMotion.ease(0.28), value: model.presented)
    }
}
