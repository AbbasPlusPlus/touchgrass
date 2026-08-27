// TGOverlay — the little app badge that fronts the cursor pill.
import SwiftUI

/// The TouchGrass mark, bare — no chip behind it. The mark is a self-contained disc of grass
/// and reads fine directly on the pill's dark glass.
struct LogoBadge: View {

    var side: CGFloat = 24

    var body: some View {
        LogoMarkView()
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
