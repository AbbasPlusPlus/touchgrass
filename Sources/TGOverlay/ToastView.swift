// TGOverlay — a single line of glass that slides down from the top of the screen and leaves.
// It never asks for anything except, occasionally, an Undo.

import SwiftUI

struct ToastView: View {
    @ObservedObject var model: ToastModel

    static let margin: CGFloat = 16
    static let height: CGFloat = 46
    static let inset: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.margin)
            pill
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .offset(y: model.presented ? 0 : -(Self.height + Self.margin + 10))
        .opacity(model.presented ? 1 : 0)
        .animation(OverlayMotion.softSpring(response: 0.5, damping: 0.84), value: model.presented)
    }

    private var pill: some View {
        HStack(spacing: 10) {
            Image(systemName: model.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))

            Text(model.text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .fixedSize()

            if let undoTitle = model.undoTitle {
                Button(undoTitle, action: model.onUndo)
                    .buttonStyle(GlassPillStyle(size: .small, tinted: true))
                    .padding(.leading, 2)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, model.undoTitle == nil ? 18 : 14)
        .padding(.vertical, model.undoTitle == nil ? 12 : 8)
        .glassSurface(Capsule(), shadowRadius: 18, shadowY: 7)
        .fixedSize()
    }
}
