// TGMenuBar — the panel that drops out of the status item on left click.
import AppKit
import SwiftUI
import TGCore

/// Owns the quick panel window: builds it lazily, anchors it under the status item,
/// and dismisses it on Escape or on a click anywhere else.
///
/// Never touches the activation policy — the panel is a `.nonactivatingPanel`, so it takes
/// key input while TouchGrass stays in the background.
@MainActor
public final class QuickPanel {

    /// Fixed width; the height comes from the SwiftUI layout, clamped to a sane range.
    public static let width: CGFloat = 340
    private static let heightRange: ClosedRange<CGFloat> = 200...460

    private let engine: BreakEngine
    private let settingsStore: SettingsStore
    private let actions: MenuBarActions

    private var window: QuickPanelWindow?
    private var hosting: NSHostingView<QuickPanelView>?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Screen rect of the status item, so an outside-click doesn't fight the button's own toggle.
    private var anchorRect: NSRect = .zero

    public init(
        engine: BreakEngine,
        settingsStore: SettingsStore,
        actions: MenuBarActions
    ) {
        self.engine = engine
        self.settingsStore = settingsStore
        self.actions = actions
    }

    // MARK: - Presentation

    public var isVisible: Bool { window?.isVisible ?? false }

    public func toggle(relativeTo button: NSStatusBarButton?) {
        isVisible ? close() : show(relativeTo: button)
    }

    public func show(relativeTo button: NSStatusBarButton?) {
        let panel = window ?? makeWindow()
        window = panel

        let size = NSSize(
            width: Self.width,
            height: min(max(hosting?.fittingSize.height ?? 0, Self.heightRange.lowerBound),
                        Self.heightRange.upperBound)
        )
        panel.setContentSize(size)

        anchorRect = button.flatMap(Self.screenRect(of:)) ?? .zero
        panel.setFrameOrigin(origin(anchor: anchorRect, size: size))
        panel.makeKeyAndOrderFront(nil)
        startMonitoring()
    }

    public func close() {
        stopMonitoring()
        window?.orderOut(nil)
    }

    // MARK: - Window

    private func makeWindow() -> QuickPanelWindow {
        let initialSize = NSSize(width: Self.width, height: Self.heightRange.lowerBound)
        let panel = QuickPanelWindow(contentRect: NSRect(origin: .zero, size: initialSize))
        panel.onCancel = { [weak self] in self?.close() }

        let root = QuickPanelView(
            engine: engine,
            store: settingsStore,
            actions: actions,
            dismiss: { [weak self] in self?.close() }
        )
        let hostingView = NSHostingView(rootView: root)
        hosting = hostingView
        let container = GlassBackground.container(cornerRadius: 16, content: hostingView)

        let contentView = NSView(frame: NSRect(origin: .zero, size: initialSize))
        contentView.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        panel.contentView = contentView
        return panel
    }

    /// Centre the panel under the status item, then keep it inside the screen.
    private func origin(anchor: NSRect, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return .zero }

        let gap: CGFloat = 6
        let anchorRect = anchor == .zero
            ? NSRect(x: visible.maxX - 40, y: visible.maxY, width: 24, height: 1)
            : anchor

        var x = anchorRect.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        var y = anchorRect.minY - size.height - gap
        if y < visible.minY + 8 { y = visible.minY + 8 }
        return NSPoint(x: x, y: y)
    }

    private static func screenRect(of button: NSStatusBarButton) -> NSRect? {
        guard let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    // MARK: - Dismiss on outside click

    private func startMonitoring() {
        stopMonitoring()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.handleOutsideClick()
        }
        // Catches clicks landing in TouchGrass's *own* other windows (Settings, Onboarding).
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.window !== self.window { self.handleOutsideClick() }
            return event
        }
    }

    private func handleOutsideClick() {
        // A click on the status item itself is the button's business: it toggles us. Closing
        // here on mouse-down would let the button's mouse-up immediately reopen the panel.
        let location = NSEvent.mouseLocation
        if anchorRect != .zero, anchorRect.insetBy(dx: -2, dy: -2).contains(location) { return }
        close()
    }

    private func stopMonitoring() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
