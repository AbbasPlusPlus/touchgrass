// TGOverlay — the little app badge that fronts the cursor pill.
import SwiftUI

/// A rounded-square chip carrying the TouchGrass mark: matcha→pollen behind, the mark on top,
/// a hairline rim so it separates from whatever glass it is sitting on.
///
/// The mark is green and so is half the gradient, so the chip is deliberately *pale* where the
/// mark's light crescent lands and warm where its dark mass does — that contrast is what makes
/// it legible at 24 pt rather than reading as a green smudge.
struct LogoBadge: View {

    var side: CGFloat = 24

    private var corner: CGFloat { side * 0.30 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [OverlayPalette.matcha, OverlayPalette.pollen],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            LogoMarkView()
                .frame(width: side * 0.80, height: side * 0.80)
        }
        .frame(width: side, height: side)
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.tg(0xF3F1E2, opacity: 0.28), lineWidth: 0.8)
        )
        .accessibilityHidden(true)
    }
}
