// TGMenuBar — the one settings window.
import AppKit
import Combine
import SwiftUI
import TGCore

/// Hosts `SettingsView` in a single reusable `NSWindow` that remembers where the user left it.
///
/// Showing it is the only situation (with onboarding) where TouchGrass becomes a `.regular`
/// app — see `ActivationCoordinator`.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {

    private static let autosaveName = "TouchGrassSettingsWindow"
    private static let defaultSize = NSSize(width: 760, height: 540)
    /// See `OnboardingWindowController` for why a `.fullSizeContentView` window has to mask
    /// its own content. This window stays opaque, so an imperfect match just reveals the
    /// window background — the same colour the frame would have drawn there anyway.
    private static let cornerRadius: CGFloat = 16

    private let window: NSWindow
    private let selection = SettingsSelection()
    private var cancellables: Set<AnyCancellable> = []

    public init(
        settingsStore: SettingsStore,
        loginItems: LoginItemManager,
        previewSound: @escaping (SoundStyle, String) -> Void,
        onShowOnboarding: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        let root = SettingsView(
            store: settingsStore,
            loginItems: loginItems,
            selection: selection,
            previewSound: previewSound,
            onShowOnboarding: onShowOnboarding,
            onQuit: onQuit
        )

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.contentViewController = NSHostingController(rootView: root)
        window.title = selection.section.title
        // Paper, not the system window colour: the title bar is transparent, so this is what
        // shows behind it and around the split view's edges.
        window.backgroundColor = .tgPaper
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 690, height: 470)
        window.setContentSize(Self.defaultSize)
        // `.fullSizeContentView` stops AppKit clipping the content view to the window's
        // rounded corners, which lets the sidebar's material square off the bottom corners.
        // Round the content view itself instead; a layer radius tracks live resize for free.
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = Self.cornerRadius
            contentView.layer?.cornerCurve = .continuous
            contentView.layer?.masksToBounds = true
        }
        // Rounded corners and a full-screen Space don't mix — and a settings window has no
        // business being full screen, any more than System Settings does.
        window.collectionBehavior.insert(.fullScreenNone)
        window.delegate = self

        restoreFrame()

        // Keep the title bar in step with the sidebar, like System Settings.
        selection.$section
            .receive(on: DispatchQueue.main)
            .sink { [weak self] section in self?.window.title = section.title }
            .store(in: &cancellables)
    }

    // MARK: - Presentation

    public func present(selecting section: SettingsSection? = nil) {
        if let section { selection.section = section }
        ActivationCoordinator.present(window)
    }

    public func close() { window.close() }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        window.saveFrame(usingName: Self.autosaveName)
        ActivationCoordinator.didClose(window)
    }

    // MARK: - Frame memory

    /// `setFrameAutosaveName` only restores when a frame was actually saved, so centre the
    /// window on genuine first launch instead of letting AppKit cascade it into a corner.
    private func restoreFrame() {
        let key = "NSWindow Frame \(Self.autosaveName)"
        let hasSavedFrame = UserDefaults.standard.string(forKey: key) != nil
        window.setFrameAutosaveName(Self.autosaveName)
        if hasSavedFrame {
            window.setFrameUsingName(Self.autosaveName)
        } else {
            window.center()
        }
    }
}
