// TGMenuBar — the TouchGrass mark, as a SwiftUI view.
import SwiftUI

/// The approved logo (`Support/logo/touchgrass-mark.svg`) drawn as vectors, so it is crisp at
/// 18 pt in the cursor pill's badge and at 78 pt on the onboarding hero. The path data lives
/// in `LogoMarkGeometry`; this is only the SwiftUI wrapper.
struct LogoMark: View {

    /// Drawn edge to edge; callers set the frame.
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
