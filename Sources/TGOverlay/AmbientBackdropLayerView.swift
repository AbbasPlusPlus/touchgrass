// TGOverlay — the NSView that hosts an ambient Core Animation backdrop.
// Rebuilds its layer tree only when the backdrop or the view's size actually changes.

import AppKit

final class AmbientBackdropLayerView: NSView {

    var backdrop: AmbientBackdrop? {
        didSet { if backdrop != oldValue { builtSize = .zero; needsLayout = true } }
    }

    private var builtSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Required for CIFilter-based layer blurs to have any effect.
        layerUsesCoreImageFilters = true
        layer?.masksToBounds = true
        layer?.backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        guard size != builtSize else { return }
        builtSize = size
        rebuild(size: size)
    }

    private func rebuild(size: CGSize) {
        guard let host = layer, let backdrop else { return }
        host.sublayers?.forEach { $0.removeFromSuperlayer() }

        // Layers are authored in top-left coordinates, like the rest of the module.
        host.isGeometryFlipped = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for sublayer in AmbientBackdropBuilder.layers(for: backdrop,
                                                      size: size,
                                                      animated: !OverlayMotion.reduceMotion) {
            host.addSublayer(sublayer)
        }
        CATransaction.commit()
    }
}
