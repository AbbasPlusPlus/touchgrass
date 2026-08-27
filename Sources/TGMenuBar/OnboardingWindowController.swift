// TGMenuBar — the first-run window.
import AppKit
import SwiftUI
import TGCore

/// A small, fixed-size window for the three setup questions.
///
/// Like Settings, this is allowed to activate the app — it's the one moment the user is
/// deliberately looking at TouchGrass rather than through it.
///
/// **Shape.** A `.fullSizeContentView` window hands its whole frame to the content view, and
/// AppKit then stops masking that view to the window's rounded corners — so a layer-backed
/// `NSHostingView` painting a saturated gradient right up to the top edge draws square
/// corners that stick out past the window's own rounded ones. The fix is to stop having two
/// shapes: the window paints nothing at all (`isOpaque = false`, clear background) and the
/// content view's rounded layer *is* the window's visible shape. `hasShadow` still gives the
/// usual drop shadow, computed from the opaque part of what we drew.
@MainActor
public final class OnboardingWindowController: NSObject, NSWindowDelegate {

    private static let size = NSSize(width: 560, height: 480)
    /// Matches the corner macOS 26 gives a window this size. Being a point or two off is
    /// harmless now that nothing is drawn behind it — there is no square edge left to reveal.
    private static let cornerRadius: CGFloat = 16

    private let window: NSWindow

    public init(settingsStore: SettingsStore, loginItems: LoginItemManager) {
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        let root = OnboardingView(
            store: settingsStore,
            loginItems: loginItems,
            onFinish: { [weak self] in self?.window.close() }
        )
        // An `NSHostingView` rather than an `NSHostingController`: the controller keeps forcing
        // the window to its fitting size, which fights the fixed 560×480 onboarding layout.
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        hosting.autoresizingMask = [.width, .height]
        // Stop SwiftUI's intrinsic size from driving the window: the onboarding window is a
        // fixed 560×480 and the layout should fit itself into that, not the other way round.
        hosting.sizingOptions = []
        // The content view's layer carries the whole window shape — see the note above.
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = Self.cornerRadius
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true

        window.contentView = hosting
        window.title = "Welcome to TouchGrass"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        // Nothing but the content view draws. Anything the window painted itself would be a
        // second, square-cornered shape sitting behind the first.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // `.fullSizeContentView` makes the content view span the whole window, title bar
        // included — so size the *frame*, not the content rect, or the view ends up taller
        // than the layout it hosts.
        window.setFrame(NSRect(origin: .zero, size: Self.size), display: false)
        window.center()
        window.delegate = self
    }

    public func present() {
        ActivationCoordinator.present(window)
        // A transparent window's shadow is traced from what it drew; the first trace happens
        // before SwiftUI's first paint, so ask for another one.
        window.invalidateShadow()
    }

    public func windowWillClose(_ notification: Notification) {
        ActivationCoordinator.didClose(window)
    }
}
