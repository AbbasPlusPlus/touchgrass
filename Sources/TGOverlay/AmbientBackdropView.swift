// TGOverlay — SwiftUI wrapper for the Core Animation ambient backdrops.

import AppKit
import SwiftUI

struct AmbientBackdropView: NSViewRepresentable {
    let backdrop: AmbientBackdrop

    func makeNSView(context: Context) -> AmbientBackdropLayerView {
        let view = AmbientBackdropLayerView(frame: .zero)
        view.backdrop = backdrop
        return view
    }

    func updateNSView(_ view: AmbientBackdropLayerView, context: Context) {
        view.backdrop = backdrop
    }
}
