// TGMenuBar — the first-run window.
import AppKit
import SwiftUI
import TGCore

/// A small, fixed-size window for the three setup questions.
///
/// Like Settings, this is allowed to activate the app — it's the one moment the user is
/// deliberately looking at TouchGrass rather than through it.
@MainActor
public final class OnboardingWindowController: NSObject, NSWindowDelegate {

    private static let size = NSSize(width: 560, height: 480)

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
        window.contentView = hosting
        window.title = "Welcome to TouchGrass"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
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
    }

    public func windowWillClose(_ notification: Notification) {
        ActivationCoordinator.didClose(window)
    }
}
