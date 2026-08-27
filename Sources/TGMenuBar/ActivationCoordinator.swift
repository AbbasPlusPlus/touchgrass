// TGMenuBar — the ONE place in the app that is allowed to change the activation policy.
import AppKit

/// TouchGrass runs as an `.accessory` app (no Dock icon, LSUIElement). Two windows need real
/// focus and a menu bar: Settings and Onboarding. For those — and only those — we flip to
/// `.regular`, show, activate, and flip back once the last of them closes.
///
/// Overlay/panel code must never call this: activating steals focus across Spaces, which is
/// exactly the interruption this app is trying not to be.
@MainActor
public enum ActivationCoordinator {

    private static var presented: Set<ObjectIdentifier> = []

    /// Becomes a regular app, shows the window, then activates. Order matters: the policy has
    /// to change before ordering front or the window comes up without a menu bar.
    public static func present(_ window: NSWindow) {
        presented.insert(ObjectIdentifier(window))
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Call from the window's `windowWillClose`. Reverts to `.accessory` when nothing is left.
    public static func didClose(_ window: NSWindow) {
        presented.remove(ObjectIdentifier(window))
        guard presented.isEmpty else { return }
        // Defer past the close so AppKit isn't mid-teardown when the policy changes.
        DispatchQueue.main.async {
            guard presented.isEmpty else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// True while a Settings/Onboarding window is on screen.
    public static var hasPresentedWindows: Bool { !presented.isEmpty }
}
