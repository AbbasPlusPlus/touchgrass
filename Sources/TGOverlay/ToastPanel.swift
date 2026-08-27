// TGOverlay — transient notices: "Call detected on Zoom", "Timer reset while you were away".
// Never blocks, never takes key, gone in four seconds.

import AppKit
import SwiftUI

@MainActor
public final class ToastPanel {

    private let model = ToastModel()
    private var panel: OverlayPanel?
    private var dismissTask: Task<Void, Never>?
    private var isShowing = false

    public init() {
        model.onUndo = { [weak self] in
            let action = self?.undoAction
            self?.hide()
            action?()
        }
    }

    private var undoAction: (() -> Void)?

    // MARK: - Show / hide

    public func show(symbol: String,
                     text: String,
                     undoTitle: String? = nil,
                     undo: (() -> Void)? = nil,
                     duration: TimeInterval = 4) {
        model.symbol = symbol
        model.text = text
        model.undoTitle = undo == nil ? nil : (undoTitle ?? "Undo")
        undoAction = undo

        let panel = existingOrNewPanel()
        panel.present(takingKey: false)
        isShowing = true
        DispatchQueue.main.async { [weak self] in self?.model.presented = true }

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(1, duration) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    public func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        guard isShowing else { return }
        isShowing = false
        model.presented = false
        undoAction = nil
        let panel = self.panel
        let delay = OverlayMotion.reduceMotion ? 0.0 : 0.42
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard self?.isShowing == false else { return }
            panel?.dismiss()
        }
    }

    // MARK: - Panel

    private func existingOrNewPanel() -> OverlayPanel {
        let screen = ScreenID.screenUnderMouse() ?? NSScreen.main
        let frame = Self.panelFrame(on: screen)

        if let panel {
            panel.setFrame(frame, display: false)
            panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
            return panel
        }

        // Above the break overlay: a toast may need to explain why a break just went away.
        let panel = OverlayPanel(contentRect: frame, level: .screenSaver, becomesKey: true)
        let host = NSHostingView(rootView: ToastView(model: model))
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private static func panelFrame(on screen: NSScreen?) -> NSRect {
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(visible.width - 40, 760)
        let height = ToastView.margin + ToastView.height + 44
        return NSRect(x: visible.midX - width / 2,
                      y: visible.maxY - height,
                      width: width,
                      height: height)
    }
}
