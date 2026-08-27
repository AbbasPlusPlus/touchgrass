// TGOverlay — hover/press feedback for one segment inside the split capsule.
import SwiftUI

struct SegmentHoverStyle: ButtonStyle {
    let tone: BreakTone
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hovering && isEnabled ? tone.hoverWash : Color.clear)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(OverlayMotion.ease(0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}
