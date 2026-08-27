// TGMenuBar — the borderless NSPanel that hosts the quick panel.
import AppKit

/// A borderless, non-activating panel that can still take key input.
///
/// `.nonactivatingPanel` is what lets this become key *without* activating TouchGrass — the
/// same trick Spotlight uses. That matters because activating an accessory app pulls focus
/// away from whatever the user is doing, which this app must never do.
final class QuickPanelWindow: NSPanel {

    /// Invoked for Escape (via `cancelOperation`) so the owner can dismiss.
    var onCancel: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // `isFloatingPanel` resets `level` to `.floating`, so set the level afterwards.
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
    }

    /// Borderless panels refuse key status unless this is overridden.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Escape.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
