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
    /// Sized so a 15 pt summary row fits its label and its value without either truncating.
    /// The height upper bound has to clear the Stats calendar — the tallest thing the panel shows.
    public static let width: CGFloat = 376
    private static let heightRange: ClosedRange<CGFloat> = 200...700
    /// The panel's visible shape. The glass and the content view's mask must agree — see
    /// `makeWindow()` for why the mask exists at all.
    private static let cornerRadius: CGFloat = 16

    private let engine: BreakEngine
    private let settingsStore: SettingsStore
    private let statsStore: StatsStore?
    private let actions: MenuBarActions
    /// Seconds to the next wellness nudge, asked for at render time. The scheduler lives in the
    /// app, so this is a closure rather than an observed object.
    private let wellnessCountdown: () -> TimeInterval?

    private let model = QuickPanelModel()
    private var window: QuickPanelWindow?
    private var hosting: NSHostingView<QuickPanelView>?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Screen rect of the status item, so an outside-click doesn't fight the button's own toggle.
    private var anchorRect: NSRect = .zero

    public init(
        engine: BreakEngine,
        settingsStore: SettingsStore,
        statsStore: StatsStore? = nil,
        actions: MenuBarActions,
        wellnessCountdown: @escaping () -> TimeInterval? = { nil }
    ) {
        self.engine = engine
        self.settingsStore = settingsStore
        self.statsStore = statsStore
        self.actions = actions
        self.wellnessCountdown = wellnessCountdown
    }

    // MARK: - Presentation

    public var isVisible: Bool { window?.isVisible ?? false }

    public func toggle(relativeTo button: NSStatusBarButton?) {
        isVisible ? close() : show(relativeTo: button)
    }

    /// - Parameters:
    ///   - tab: opens onto this tab instead of whichever was last used. `nil` leaves it alone.
    ///   - showingCalendar: on the Stats tab, opens straight onto the month grid.
    public func show(
        relativeTo button: NSStatusBarButton?,
        selecting tab: QuickPanelTab? = nil,
        showingCalendar: Bool = false
    ) {
        if let tab {
            model.tab = tab
            model.showingCalendar = showingCalendar
        }
        let panel = window ?? makeWindow()
        window = panel

        let size = fittingSize()
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

    // MARK: - Sizing

    /// Re-measure the SwiftUI content and resize around the panel's *top* edge, so switching to
    /// a taller tab grows the panel downwards instead of sliding it up over the menu bar.
    public func resizeToFit() {
        guard let panel = window, panel.isVisible else { return }
        hosting?.invalidateIntrinsicContentSize()
        hosting?.layoutSubtreeIfNeeded()
        let top = panel.frame.maxY

        var frame = panel.frame
        frame.size = panel.frameRect(forContentRect: NSRect(origin: .zero, size: fittingSize())).size
        frame.origin.y = top - frame.height
        if let visible = panel.screen?.visibleFrame, frame.minY < visible.minY + 8 {
            frame.origin.y = visible.minY + 8
        }
        panel.setFrame(frame, display: true, animate: false)
    }

    /// Asks for a resize on the next run-loop turn: SwiftUI hasn't laid the new tab out yet at
    /// the moment the state changes, so measuring now would measure the old tab.
    private func requestResize() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.resizeToFit() }
        }
    }

    private func fittingSize() -> NSSize {
        NSSize(
            width: Self.width,
            height: min(max(hosting?.fittingSize.height ?? 0, Self.heightRange.lowerBound),
                        Self.heightRange.upperBound)
        )
    }

    // MARK: - Window

    private func makeWindow() -> QuickPanelWindow {
        let initialSize = NSSize(width: Self.width, height: Self.heightRange.lowerBound)
        let panel = QuickPanelWindow(contentRect: NSRect(origin: .zero, size: initialSize))
        panel.onCancel = { [weak self] in self?.close() }

        let root = QuickPanelView(
            engine: engine,
            store: settingsStore,
            stats: statsStore,
            model: model,
            actions: actions,
            wellnessCountdown: wellnessCountdown,
            dismiss: { [weak self] in self?.close() },
            requestResize: { [weak self] in self?.requestResize() }
        )
        let hostingView = NSHostingView(rootView: root)
        hosting = hostingView
        let container = GlassBackground.container(cornerRadius: Self.cornerRadius, content: hostingView)

        // **First-frame shape.** `hasShadow` makes AppKit trace the drop shadow from whatever
        // the window has drawn. `NSGlassEffectView` composites on the window server, and on the
        // very first frame — the one where the panel is created and ordered front in the same
        // turn — the glass has not rendered yet, so the trace falls back to the window's frame
        // rectangle and the panel gets a hard, square-cornered shadow around its rounded body.
        // Nothing re-traces it until the window is redrawn for another reason, which is why it
        // used to "fix itself" the moment the user switched apps and came back.
        //
        // Masking the content view to the same rounded rect gives the window's *own* backing
        // store the right silhouette before it is ever shown, so the first trace is already
        // correct and the shadow no longer depends on when the glass happens to come up.
        let contentView = NSView(frame: NSRect(origin: .zero, size: initialSize))
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = Self.cornerRadius
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
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
