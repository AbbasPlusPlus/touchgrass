// TGMenuBar — the status item: TouchGrass's permanent, quiet presence.
import AppKit
import Combine
import TGCore

/// Owns the `NSStatusItem` and everything hanging off it: the countdown, the quick panel,
/// the right-click menu, the settings and onboarding windows, and the global hotkeys.
///
/// All `BreakEngine` commands funnel through here and only ever run from a user action —
/// the engine is not safe to poke at startup.
@MainActor
public final class StatusBarController: NSObject {

    // MARK: - Dependencies

    private let engine: BreakEngine
    private let settingsStore: SettingsStore
    private let previewSound: (SoundStyle, String) -> Void
    private let onQuit: () -> Void
    private let onStartStop: (() -> Void)?
    private let wellnessCountdown: () -> TimeInterval?

    // MARK: - Owned objects

    private let statusItem: NSStatusItem
    private let hotkeys = HotkeyManager()
    private let loginItems = LoginItemManager()
    private var quickPanel: QuickPanel?
    private var settingsWindow: SettingsWindowController?
    private var onboardingWindow: OnboardingWindowController?
    private var cancellables: Set<AnyCancellable> = []

    /// Cached so we aren't re-rendering a bezier path every second.
    private let normalIcon = StatusBarIcon.grass()
    private let dimmedIcon = StatusBarIcon.grass(dimmed: true)
    private var lastRendered: StatusPresentation?

    // MARK: - Init

    /// - Parameters:
    ///   - previewSound: plays a sample for the Sounds page. Injected so TGMenuBar never has
    ///     to depend on TGAudio. The `String` is the event name ("start" / "end" / "preBreak").
    ///   - onQuit: what the ⌘Q / Quit item does. Defaults to `NSApp.terminate`.
    ///   - onStartStop: overrides the Start/Stop menu item. Defaults to `engine.start()/stop()`.
    ///   - wellnessCountdown: seconds until the next blink nudge, when the app knows.
    public init(
        engine: BreakEngine,
        settingsStore: SettingsStore,
        previewSound: @escaping (SoundStyle, String) -> Void = { _, _ in },
        onQuit: (() -> Void)? = nil,
        onStartStop: (() -> Void)? = nil,
        wellnessCountdown: @escaping () -> TimeInterval? = { nil }
    ) {
        self.engine = engine
        self.settingsStore = settingsStore
        self.previewSound = previewSound
        self.onQuit = onQuit ?? { NSApp.terminate(nil) }
        self.onStartStop = onStartStop
        self.wellnessCountdown = wellnessCountdown
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        makeQuickPanel()
        observe()
        render(phase: engine.phase)
    }

    // MARK: - Public surface

    /// Shows the settings window, flipping the app to `.regular` for the duration.
    public func showSettings(selecting section: SettingsSection? = nil) {
        let controller = settingsWindow ?? makeSettingsWindow()
        settingsWindow = controller
        controller.present(selecting: section)
    }

    /// Shows the three-step first-run flow.
    public func showOnboarding() {
        let controller = onboardingWindow ?? makeOnboardingWindow()
        onboardingWindow = controller
        controller.present()
    }

    /// Called by the app at launch: opens onboarding only the first time.
    public func showOnboardingIfNeeded() {
        guard !settingsStore.settings.hasCompletedOnboarding else { return }
        showOnboarding()
    }

    /// Drops the quick panel under the status item.
    public func showQuickPanel() {
        quickPanel?.show(relativeTo: statusItem.button)
    }

    public func closeQuickPanel() { quickPanel?.close() }

    // MARK: - Wiring

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = normalIcon
        button.imagePosition = .imageLeading
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("TouchGrass")
    }

    private func makeQuickPanel() {
        quickPanel = QuickPanel(
            engine: engine,
            settingsStore: settingsStore,
            actions: makeActions(),
            wellnessCountdown: wellnessCountdown
        )
    }

    private func observe() {
        // The engine republishes on every tick; the status item only needs 1 Hz.
        engine.$phase
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] phase in self?.render(phase: phase) }
            .store(in: &cancellables)

        settingsStore.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self else { return }
                // Hand edited settings to the engine. This is an assignment, not a command, so
                // it's safe at any time; the engine picks the new values up on its next tick.
                self.engine.settings = settings
                self.render(phase: self.engine.phase, force: true)
            }
            .store(in: &cancellables)

        // Re-registering Carbon hot keys is not free, and `settings` republishes on every
        // keystroke in a text field — so only react when the shortcuts themselves change.
        settingsStore.$settings
            .map(\.hotkeys)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hotkeys in self?.hotkeys.reload(with: hotkeys) }
            .store(in: &cancellables)

        hotkeys.onAction = { [weak self] action in self?.perform(action) }
    }

    // MARK: - Rendering

    private func render(phase: EnginePhase, force: Bool = false) {
        guard let button = statusItem.button else { return }
        let style = settingsStore.settings.menuBarStyle
        let presentation = StatusPresentation(phase: phase, style: style)
        guard force || presentation != lastRendered else { return }
        lastRendered = presentation

        let showsIcon = StatusPresentation.showsIcon(for: style)
        button.image = showsIcon ? (presentation.isDimmed ? dimmedIcon : normalIcon) : nil
        // A hair of air between glyph and digits; AppKit's own gap is too tight.
        button.title = presentation.menuBarText.isEmpty
            ? ""
            : (showsIcon ? " " : "") + presentation.menuBarText
        button.imagePosition = presentation.menuBarText.isEmpty ? .imageOnly : .imageLeading
        button.toolTip = presentation.tooltip
    }

    // MARK: - Clicks

    @objc private func statusItemClicked() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if isRightClick {
            quickPanel?.close()
            showMenu()
        } else {
            quickPanel?.toggle(relativeTo: statusItem.button)
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        let menu = buildMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let isStopped = engine.phase == .stopped

        add(to: menu, "Start break now", #selector(menuStartShortBreak), enabled: !isStopped)
        add(to: menu, "Start long break", #selector(menuStartLongBreak), enabled: !isStopped)
        menu.addItem(.separator())

        if engine.phase.isPaused {
            add(to: menu, "Resume", #selector(menuResume))
        } else {
            let pauseItem = NSMenuItem(title: "Pause for…", action: nil, keyEquivalent: "")
            pauseItem.isEnabled = !isStopped
            let submenu = NSMenu()
            for preset in PausePreset.allCases {
                let item = NSMenuItem(title: preset.title, action: #selector(menuPause(_:)), keyEquivalent: "")
                item.target = self
                // nil represented object == pause indefinitely.
                if let duration = preset.duration() { item.representedObject = NSNumber(value: duration) }
                item.isEnabled = !isStopped
                submenu.addItem(item)
            }
            pauseItem.submenu = submenu
            menu.addItem(pauseItem)
        }

        menu.addItem(.separator())
        add(to: menu, "Settings…", #selector(menuSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        add(to: menu, isStopped ? "Start TouchGrass" : "Stop TouchGrass", #selector(menuStartStop))
        add(to: menu, "Quit TouchGrass", #selector(menuQuit), keyEquivalent: "q")
        return menu
    }

    @discardableResult
    private func add(
        to menu: NSMenu,
        _ title: String,
        _ action: Selector,
        keyEquivalent: String = "",
        enabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
        return item
    }

    // MARK: - Commands

    /// The one place engine commands are issued. Every closure here runs from a user action.
    private func makeActions() -> MenuBarActions {
        MenuBarActions(
            startBreak: { [weak self] kind in self?.engine.startBreakNow(kind) },
            snooze: { [weak self] seconds in self?.engine.snooze(seconds) },
            skipOrEnd: { [weak self] in
                guard let self else { return }
                self.engine.phase.isInBreak ? self.engine.endBreakEarly() : self.engine.skipBreak()
            },
            pause: { [weak self] duration in self?.engine.pauseManually(for: duration) },
            resume: { [weak self] in self?.engine.resumeManually() },
            toggleRunning: { [weak self] in self?.toggleRunning() },
            openSettings: { [weak self] in self?.showSettings() },
            openOnboarding: { [weak self] in self?.showOnboarding() },
            quit: { [weak self] in self?.onQuit() }
        )
    }

    private func toggleRunning() {
        if let onStartStop { onStartStop(); return }
        engine.phase == .stopped ? engine.start() : engine.stop()
    }

    private func perform(_ action: HotkeyAction) {
        let actions = makeActions()
        switch action {
        case .togglePause:
            engine.phase.isPaused ? actions.resume() : actions.pause(nil)
        case .startBreak:
            actions.startBreak(.short)
        case .startLongBreak:
            actions.startBreak(.long)
        case .addMinute:
            actions.snooze(60)
        case .skipOrEndBreak:
            actions.skipOrEnd()
        case .openQuickPanel:
            quickPanel?.toggle(relativeTo: statusItem.button)
        }
    }

    // MARK: - Menu targets

    @objc private func menuStartShortBreak() { engine.startBreakNow(.short) }
    @objc private func menuStartLongBreak() { engine.startBreakNow(.long) }
    @objc private func menuResume() { engine.resumeManually() }
    @objc private func menuPause(_ sender: NSMenuItem) {
        engine.pauseManually(for: (sender.representedObject as? NSNumber)?.doubleValue)
    }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuStartStop() { toggleRunning() }
    @objc private func menuQuit() { onQuit() }

    // MARK: - Windows

    private func makeSettingsWindow() -> SettingsWindowController {
        SettingsWindowController(
            settingsStore: settingsStore,
            loginItems: loginItems,
            previewSound: previewSound,
            onShowOnboarding: { [weak self] in self?.showOnboarding() },
            onQuit: { [weak self] in self?.onQuit() }
        )
    }

    private func makeOnboardingWindow() -> OnboardingWindowController {
        OnboardingWindowController(settingsStore: settingsStore, loginItems: loginItems)
    }
}
