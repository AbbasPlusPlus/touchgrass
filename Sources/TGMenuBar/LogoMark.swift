// TGMenuBar — the TouchGrass mark, as a SwiftUI view.
import SwiftUI

/// The approved logo (`Support/logo/touchgrass-mark.svg`) drawn as vectors, so it is crisp at
/// 18 pt in the menu bar and at 78 pt on the onboarding hero. The path data lives in
/// `LogoMarkData` / `LogoMarkGeometry`; this is only the SwiftUI wrapper.
struct LogoMark: View {

    /// Drawn edge to edge; callers set the frame.
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
