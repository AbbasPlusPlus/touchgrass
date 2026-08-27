// TGOverlay — blink and posture nudges: small, centred, self-dismissing, never focus-stealing.
// Optionally dims the screen behind them so the eye is drawn to the middle.

import AppKit
import SwiftUI
import TGCore

@MainActor
public final class WellnessNudgeController {

    private var nudgePanels: [String: OverlayPanel] = [:]
    private var dimPanels: [String: OverlayPanel] = [:]
    private var dismissTask: Task<Void, Never>?

    private static let dimTarget: CGFloat = 0.35

    public init() {}

    // MARK: - Show

    public func show(_ kind: WellnessKind, dimsScreen: Bool, mainScreenOnly: Bool) {
        hide(animated: false)

        let screens: [NSScreen]
        if mainScreenOnly {
            screens = [ScreenID.screenUnderMouse() ?? NSScreen.main].compactMap { $0 }
        } else {
            screens = NSScreen.screens
        }
        guard !screens.isEmpty else { return }

        if dimsScreen {
            for screen in NSScreen.screens {
                let id = ScreenID.uuid(for: screen)
                let panel = OverlayPanel(contentRect: screen.frame, level: .floating - 1,
                                         becomesKey: false, clickThrough: true)
                let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
                view.wantsLayer = true
                view.layer?.backgroundColor = NSColor.black.cgColor
                panel.contentView = view
                panel.alphaValue = 0
                panel.present(takingKey: false)
                dimPanels[id] = panel
                OverlayMotion.fade(panel, to: Self.dimTarget, duration: 0.5)
            }
        }

        for screen in screens {
            let id = ScreenID.uuid(for: screen)
            let size = kind == .blink ? BlinkNudgeView.size : PostureNudgeView.size
            let padded = CGSize(width: size.width + 60, height: size.height + 60)
            let frame = NSRect(x: screen.frame.midX - padded.width / 2,
                               y: screen.frame.midY - padded.height / 2,
                               width: padded.width, height: padded.height)
            let panel = OverlayPanel(contentRect: frame, level: .floating,
                                     becomesKey: false, clickThrough: true)
            panel.contentView = Self.host(for: kind, size: padded)
            panel.alphaValue = 1        // the view springs itself in; the window does not fade
            panel.present(takingKey: false)
            nudgePanels[id] = panel
        }

        let lifetime: TimeInterval = kind == .blink ? 2.9 : 3.6
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(lifetime * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hide(animated: true)
        }
    }

    // MARK: - Hide

    public func hide(animated: Bool = true) {
        dismissTask?.cancel()
        dismissTask = nil

        let closing = Array(nudgePanels.values) + Array(dimPanels.values)
        nudgePanels.removeAll()
        dimPanels.removeAll()
        guard !closing.isEmpty else { return }

        for panel in closing {
            OverlayMotion.fade(panel, to: 0, duration: animated ? 0.45 : 0) {
                panel.dismiss()
                panel.contentView = nil
            }
        }
    }

    // MARK: - Hosting

    private static func host(for kind: WellnessKind, size: CGSize) -> NSView {
        let container: NSHostingView<AnyView>
        switch kind {
        case .blink:   container = NSHostingView(rootView: AnyView(centred(BlinkNudgeView())))
        case .posture: container = NSHostingView(rootView: AnyView(centred(PostureNudgeView())))
        }
        container.frame = NSRect(origin: .zero, size: size)
        container.autoresizingMask = [.width, .height]
        return container
    }

    private static func centred<V: View>(_ view: V) -> some View {
        view.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
