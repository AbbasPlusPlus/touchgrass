// TGOverlay — one break panel per display, kept honest across hot-plugs.
//
// Panels are keyed by display UUID, not by NSScreen index: indices reshuffle whenever a display
// wakes, changes resolution, or a dock is unplugged. On `didChangeScreenParameters` we debounce
// 250 ms (ghost-screen storms are real), then diff the UUID set: add, resize, close.

import AppKit
import SwiftUI
import TGCore

@MainActor
public final class BreakOverlayController {

    public let model = BreakViewModel()

    public private(set) var isShowing = false

    private var panels: [String: OverlayPanel] = [:]
    private var hosts: [String: NSHostingView<BreakView>] = [:]
    private var primaryScreenID: String?

    private var screenObserver: NSObjectProtocol?
    private var rebuildWork: DispatchWorkItem?

    private let fadeInDuration: Double = 0.8
    private let fadeOutDuration: Double = 0.5

    public init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    // MARK: - Show / hide

    public func show() {
        guard !isShowing else { return }
        isShowing = true
        primaryScreenID = ScreenID.screenUnderMouse().map(ScreenID.uuid(for:))

        for screen in NSScreen.screens {
            let id = ScreenID.uuid(for: screen)
            let panel = makePanel(for: screen, id: id)
            panels[id] = panel
            panel.alphaValue = 0
            panel.present(takingKey: id == primaryScreenID)
        }
        // If the pointer was on a screen we somehow didn't build, make sure something has key.
        if primaryScreenID == nil || panels[primaryScreenID ?? ""] == nil {
            panels.values.first?.present(takingKey: true)
        }

        for panel in panels.values {
            OverlayMotion.fade(panel, to: 1, duration: fadeInDuration)
        }
    }

    public func hide(completion: (() -> Void)? = nil) {
        guard isShowing else { completion?(); return }
        isShowing = false
        model.endBreak()
        rebuildWork?.cancel()
        rebuildWork = nil

        let closing = panels
        panels.removeAll()
        hosts.removeAll()
        primaryScreenID = nil

        guard !closing.isEmpty else { completion?(); return }
        var pending = closing.count
        for panel in closing.values {
            OverlayMotion.fade(panel, to: 0, duration: fadeOutDuration) {
                panel.dismiss()
                panel.contentView = nil
                pending -= 1
                if pending == 0 { completion?() }
            }
        }
    }

    // MARK: - Panel construction

    private func makePanel(for screen: NSScreen, id: String) -> OverlayPanel {
        let panel = OverlayPanel(contentRect: screen.frame, level: .screenSaver, becomesKey: true)
        let host = NSHostingView(rootView: breakView(for: screen, id: id))
        host.frame = NSRect(origin: .zero, size: screen.frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.setFrame(screen.frame, display: false)
        hosts[id] = host
        return panel
    }

    private func breakView(for screen: NSScreen, id: String) -> BreakView {
        BreakView(model: model,
                  role: id == primaryScreenID ? .primary : .secondary,
                  wallpaperURL: WallpaperLoader.url(for: screen),
                  topInset: screen.safeAreaInsets.top)
    }

    // MARK: - Display hot-plug

    private func scheduleRebuild() {
        guard isShowing else { return }
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.rebuildForCurrentScreens() }
        }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func rebuildForCurrentScreens() {
        guard isShowing else { return }
        let screens = NSScreen.screens
        var live: [String: NSScreen] = [:]
        for screen in screens { live[ScreenID.uuid(for: screen)] = screen }

        // The pointer may now be on a different display, or the old primary may be gone.
        if let current = primaryScreenID, live[current] == nil {
            primaryScreenID = ScreenID.screenUnderMouse().map(ScreenID.uuid(for:))
        }

        // Close panels for departed displays.
        for (id, panel) in panels where live[id] == nil {
            panel.dismiss()
            panel.contentView = nil
            panels.removeValue(forKey: id)
            hosts.removeValue(forKey: id)
        }

        // Add or re-fit the rest.
        for (id, screen) in live {
            if let panel = panels[id] {
                if panel.frame != screen.frame {
                    panel.setFrame(screen.frame, display: true)
                    hosts[id]?.frame = NSRect(origin: .zero, size: screen.frame.size)
                }
                hosts[id]?.rootView = breakView(for: screen, id: id)
                panel.reassert(takingKey: id == primaryScreenID)
            } else {
                let panel = makePanel(for: screen, id: id)
                panels[id] = panel
                panel.alphaValue = 0
                panel.present(takingKey: id == primaryScreenID)
                OverlayMotion.fade(panel, to: 1, duration: 0.35)
            }
        }
    }
}
