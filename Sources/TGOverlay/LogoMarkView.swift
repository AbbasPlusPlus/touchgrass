// TGOverlay — the TouchGrass mark, as a SwiftUI view.
import SwiftUI

/// The badge on the cursor pill. Same five paths as the app icon and the About page; see
/// `LogoMarkGeometry`.
struct LogoMarkView: View {

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let side = min(size.width, size.height)
            let dropSlivers = side < LogoMarkGeometry.sliverFloor

            context.clip(to: Path(LogoMarkGeometry.discPath(in: rect, flipped: false)))
            for blade in LogoMarkGeometry.blades {
                let hex = (dropSlivers && blade.isSliver) ? 0x27521F : blade.hex
                context.fill(Path(LogoMarkGeometry.cgPath(blade.commands, in: rect, flipped: false)),
                             with: .color(.tg(UInt32(hex))))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
