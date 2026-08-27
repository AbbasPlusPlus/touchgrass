// TGOverlay — the last ten seconds, carried on the pointer so it can't be missed and can't be
// in the way. A 60 Hz timer runs only while the pill is on screen; the rest of the time it is
// invalidated, so idle CPU stays at zero.

import AppKit
import SwiftUI

@MainActor
public final class CursorPill {

    private let model = CursorPillModel()
    private var panel: OverlayPanel?
    private var follower: Timer?
    private var hideWork: DispatchWorkItem?

    public private(set) var isShowing = false

    public init() {}

    // MARK: - Show / update / hide

    public func show(symbol: String, text: String) {
        hideWork?.cancel()
        hideWork = nil
        model.symbol = symbol
        model.text = text

        let panel = existingOrNewPanel()
        reposition(panel)
        panel.present(takingKey: false)
        isShowing = true
        DispatchQueue.main.async { [weak self] in self?.model.presented = true }
        startFollowing()
    }

    public func update(symbol: String? = nil, text: String) {
        if let symbol { model.symbol = symbol }
        model.text = text
    }

    public func hide() {
        guard isShowing else { return }
        isShowing = false
        model.presented = false
        stopFollowing()

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isShowing else { return }
            self.panel?.dismiss()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + OverlayMotion.duration(0.3), execute: work)
    }

    // MARK: - Following

    private func startFollowing() {
        guard follower == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, self.isShowing else { return }
                self.reposition(panel)
            }
        }
        // .common so the pill keeps up while a menu or drag is tracking.
        RunLoop.main.add(timer, forMode: .common)
        follower = timer
    }

    private func stopFollowing() {
        follower?.invalidate()
        follower = nil
    }

    /// Sits down-and-right of the hot spot, flipping to the other side near a screen edge.
    private func reposition(_ panel: OverlayPanel) {
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        var origin = CGPoint(x: mouse.x + 18 - CursorPillView.inset,
                             y: mouse.y - 18 - size.height + CursorPillView.inset)

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let bounds = screen.frame
            if origin.x + size.width > bounds.maxX - 8 { origin.x = mouse.x - 18 - size.width + CursorPillView.inset * 2 }
            if origin.y < bounds.minY + 8 { origin.y = mouse.y + 18 - CursorPillView.inset }
            origin.x = min(max(origin.x, bounds.minX - CursorPillView.inset), bounds.maxX - size.width + CursorPillView.inset)
            origin.y = min(max(origin.y, bounds.minY - CursorPillView.inset), bounds.maxY - size.height + CursorPillView.inset)
        }
        panel.setFrameOrigin(origin)
    }

    // MARK: - Panel

    private func existingOrNewPanel() -> OverlayPanel {
        if let panel { return panel }
        let size = CGSize(width: CursorPillView.size.width + CursorPillView.inset * 2,
                          height: CursorPillView.size.height + CursorPillView.inset * 2)
        let frame = NSRect(origin: NSEvent.mouseLocation, size: size)
        // Above the break overlay so the pill survives into a break if one is already up.
        let panel = OverlayPanel(contentRect: frame, level: .screenSaver,
                                 becomesKey: false, clickThrough: true)
        let host = NSHostingView(rootView: CursorPillView(model: model))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel
        return panel
    }
}
