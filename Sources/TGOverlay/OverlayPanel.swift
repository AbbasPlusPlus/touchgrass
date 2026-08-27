// TGOverlay — the one window recipe every TouchGrass surface uses.
//
// Rules baked in here (all verified on macOS 26, see research/03-macos-tech-landscape.md §1):
//   • .borderless + .nonactivatingPanel so keyboard can reach us without stealing app activation.
//   • canBecomeKey must be overridden for borderless panels, or Esc never arrives.
//   • isFloatingPanel resets `level`, so `level` is assigned LAST.
//   • constrainFrameRect must be overridden or AppKit slides the panel below the menu bar.
//   • Never, ever NSApp.activate().

import AppKit

public final class OverlayPanel: NSPanel {

    private let becomesKey: Bool
    private let assertedLevel: NSWindow.Level
    private var observers: [NSObjectProtocol] = []

    // MARK: - Init

    public init(contentRect: NSRect,
                level: NSWindow.Level = .screenSaver,
                becomesKey: Bool = true,
                clickThrough: Bool = false,
                shadow: Bool = false) {
        self.becomesKey = becomesKey
        self.assertedLevel = level

        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true          // must come before `level` — it rewrites it to .floating
        self.level = level              // ← last

        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        canHide = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = shadow
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = clickThrough
        // Keep break screens out of screen recordings where the OS still honours it.
        sharingType = .none
        // Borderless panels have no titlebar accessories to worry about; keep the shadow crisp.
        contentView?.wantsLayer = true

        installReassertObservers()
    }

    deinit {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        for token in observers {
            center.removeObserver(token)
            workspace.removeObserver(token)
        }
    }

    // MARK: - Key / main

    public override var canBecomeKey: Bool { becomesKey }
    public override var canBecomeMain: Bool { false }

    /// AppKit otherwise clamps borderless panels below the menu bar, leaving a visible strip.
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    // MARK: - Presentation

    /// Shows the panel without activating the app. `takingKey` routes keyboard to us
    /// (legal for a `.nonactivatingPanel`, and required for the double-Escape monitor).
    public func present(takingKey: Bool = false) {
        orderFrontRegardless()
        if takingKey && becomesKey { makeKey() }
    }

    public func dismiss() {
        orderOut(nil)
    }

    /// Re-applies level + ordering. Cheap; safe to call often.
    public func reassert(takingKey: Bool = false) {
        guard isVisible else { return }
        if level != assertedLevel { level = assertedLevel }
        orderFrontRegardless()
        if takingKey && becomesKey && !isKeyWindow { makeKey() }
    }

    // MARK: - Re-assertion triggers

    private func installReassertObservers() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter

        // Losing key (Spotlight, a notification banner) can drop us behind. Re-order, don't re-take key.
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification,
                                           object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reassert() }
        })

        // Space switches and wake both re-stack windows underneath us.
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                              object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reassert(takingKey: true) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                              object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reassert(takingKey: true) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                              object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reassert(takingKey: true) }
        })
    }
}
