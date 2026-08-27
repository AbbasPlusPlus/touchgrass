// TGOverlay — the T-60s notification card: a small non-activating panel that springs down from
// the top-right of whichever screen the pointer is on, then gets out of the way by itself.

import AppKit
import SwiftUI
import TGCore

@MainActor
public final class PreBreakCard {

    public var onStart: () -> Void = {}
    public var onSnooze: (TimeInterval) -> Void = { _ in }

    private let model = PreBreakCardModel()
    private var panel: OverlayPanel?
    private var autoHide: Task<Void, Never>?

    public private(set) var isShowing = false

    public init() {
        model.onStart = { [weak self] in
            self?.hide()
            self?.onStart()
        }
        model.onSnooze = { [weak self] seconds in
            self?.hide()
            self?.onSnooze(seconds)
        }
        model.onDismiss = { [weak self] in self?.hide() }
    }

    // MARK: - Show / hide

    public func show(kind: BreakKind,
                     secondsLeft: Int,
                     snoozesRemaining: Int,
                     visibleSeconds: TimeInterval,
                     compact: Bool = false,
                     breakDuration: TimeInterval = 0) {
        model.kind = kind
        model.secondsLeft = secondsLeft
        if !isShowing || secondsLeft > model.totalSeconds { model.totalSeconds = max(1, secondsLeft) }
        model.snoozesRemaining = snoozesRemaining
        model.compact = compact
        if breakDuration > 0 { model.breakDuration = breakDuration }
        if !isShowing { model.copy = PreBreakCardModel.randomCopy(for: kind) }

        let panel = existingOrNewPanel()
        panel.present(takingKey: false)
        isShowing = true

        // One runloop hop so the spring animates from the off-screen position.
        DispatchQueue.main.async { [weak self] in self?.model.presented = true }

        autoHide?.cancel()
        let seconds = max(1, visibleSeconds)
        autoHide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    public func update(secondsLeft: Int, snoozesRemaining: Int) {
        model.secondsLeft = secondsLeft
        model.snoozesRemaining = snoozesRemaining
    }

    public func hide() {
        autoHide?.cancel()
        autoHide = nil
        guard isShowing else { return }
        isShowing = false
        model.presented = false
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

        let panel = OverlayPanel(contentRect: frame, level: .floating, becomesKey: true)
        let host = NSHostingView(rootView: PreBreakCardView(model: model))
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private static func panelFrame(on screen: NSScreen?) -> NSRect {
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = PreBreakCardView.width + PreBreakCardView.inset * 2
        let height = PreBreakCardView.margin + PreBreakCardView.maxHeight + 48
        return NSRect(x: visible.maxX - PreBreakCardView.margin - PreBreakCardView.width - PreBreakCardView.inset,
                      y: visible.maxY - height,
                      width: width,
                      height: height)
    }
}
