// TGOverlay — the TouchGrass mark, as a SwiftUI view.
import SwiftUI

/// The badge on the cursor pill. Same 46 paths as the app icon and the About page; see
/// `LogoMarkGeometry`.
struct LogoMarkView: View {

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            for piece in LogoMarkGeometry.pieces(in: rect, flipped: false) {
                context.fill(Path(piece.path), with: .color(Color(cgColor: piece.color)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
