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
    /// Optional: without it the quick panel drops the Now/Stats control and shows only "Now".
    private let statsStore: StatsStore?
    private let previewSound: (SoundStyle, String) -> Void
    private let onQuit: () -> Void
    private let onStartStop: (() -> Void)?
    /// Wired by the app. The Now panel no longer carries a wellness row ('s doesn't
    /// either); this is kept so the wiring survives for the Stats surface.
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
    /// Only the status item's own strings. The panel's countdown ticks every second; the
    /// status item is minute-granular, so diffing the whole presentation would repaint 60×
    /// more often than anything actually changes.
    private var lastRenderedKey: String?

    // MARK: - Init

    /// - Parameters:
    ///   - statsStore: backs the quick panel's Stats tab. `nil` hides the tab entirely.
    ///   - previewSound: plays a sample for the Sounds page. Injected so TGMenuBar never has
    ///     to depend on TGAudio. The `String` is the event name ("start" / "end" / "preBreak").
    ///   - onQuit: what the ⌘Q / Quit item does. Defaults to `NSApp.terminate`.
    ///   - onStartStop: overrides the Start/Stop menu item. Defaults to `engine.start()/stop()`.
    ///   - wellnessCountdown: seconds until the next blink nudge, when the app knows.
    public init(
        engine: BreakEngine,
        settingsStore: SettingsStore,
        statsStore: StatsStore? = nil,
        previewSound: @escaping (SoundStyle, String) -> Void = { _, _ in },
        onQuit: (() -> Void)? = nil,
        onStartStop: (() -> Void)? = nil,
        wellnessCountdown: @escaping () -> TimeInterval? = { nil }
    ) {
        self.engine = engine
        self.settingsStore = settingsStore
        self.statsStore = statsStore
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

    /// Drops the quick panel under the status item, optionally onto a particular tab.
    public func showQuickPanel(selecting tab: QuickPanelTab? = nil, showingCalendar: Bool = false) {
        quickPanel?.show(relativeTo: statusItem.button, selecting: tab, showingCalendar: showingCalendar)
    }

    public func closeQuickPanel() { quickPanel?.close() }

    // MARK: - Wiring

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = normalIcon
        button.imagePosition = .imageLeading
        // Monospaced digits so `24m` → `9m` doesn't make the whole menu bar shuffle.
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
            statsStore: statsStore,
            actions: makeActions()
        )
    }

    private func observe() {
        // The engine republishes on every tick; the status item only needs 1 Hz — and the
        // `lastRenderedKey` diff drops all but the one tick a minute that changes anything.
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
                // The statr judges sessions against the interval, so it needs the live value.
                self.statsStore?.settings = settings
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
        guard force || presentation.statusItemKey != lastRenderedKey else { return }
        lastRenderedKey = presentation.statusItemKey

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

    // MARK: - Right-click menu

    /// Ordered the way  orders it: what's queued, then the four things you can do to
    /// it, then the app-level items. Verbs first, housekeeping last.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let phase = engine.phase
        let isStopped = phase == .stopped

        // A disabled header rather than a title: it states the situation the rest of the menu
        // is about ("Short break · 30 secs · in 22m") without pretending to be clickable.
        let header = NSMenuItem(title: menuHeader(phase), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        add(to: menu, "Start this break now", #selector(menuStartThisBreak), enabled: !isStopped)

        addSubmenu(to: menu, "Delay break", enabled: engine.canDelayNow) { submenu in
            for minutes in [1, 5, 15] {
                let item = NSMenuItem(
                    title: "+\(minutes) \(minutes == 1 ? "minute" : "minutes")",
                    action: #selector(menuDelay(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = NSNumber(value: Double(minutes) * 60)
                submenu.addItem(item)
            }
        }

        if phase.isPaused {
            add(to: menu, "Resume", #selector(menuResume))
        } else {
            addSubmenu(to: menu, "Pause breaks", enabled: !isStopped) { submenu in
                for preset in PausePreset.allCases {
                    let item = NSMenuItem(
                        title: preset.menuTitle,
                        action: #selector(menuPause(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    // nil represented object == pause indefinitely.
                    if let duration = preset.duration() {
                        item.representedObject = NSNumber(value: duration)
                    }
                    submenu.addItem(item)
                }
            }
        }

        addSubmenu(to: menu, "Take a break for", enabled: !isStopped && !phase.isInBreak) { submenu in
            for minutes in [1, 3, 5, 10] {
                let item = NSMenuItem(
                    title: "\(minutes) \(minutes == 1 ? "minute" : "minutes")",
                    action: #selector(menuCustomBreak(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = NSNumber(value: Double(minutes) * 60)
                submenu.addItem(item)
            }
        }

        menu.addItem(.separator())
        add(to: menu, isStopped ? "Start TouchGrass" : "Stop TouchGrass", #selector(menuStartStop))

        menu.addItem(.separator())
        add(to: menu, "About…", #selector(menuAbout))
        add(to: menu, "Settings…", #selector(menuSettings), keyEquivalent: ",")

        menu.addItem(.separator())
        add(to: menu, "Quit", #selector(menuQuit), keyEquivalent: "q")
        return menu
    }

    /// The disabled first line: which break is queued, how long it lasts, and when it lands.
    /// Minute-granular like the status item — the menu is not the place for a ticking clock.
    private func menuHeader(_ phase: EnginePhase) -> String {
        switch phase {
        case .stopped:
            return "TouchGrass is off"
        case .running(let kind, let remaining), .preBreak(let kind, let remaining):
            return "\(Self.kindTitle(kind)) · \(TGFormat.duration(breakLength(kind))) · in \(TGFormat.menuBar(remaining))"
        case .waitingForActivityToStop(let kind, let hint):
            return "\(Self.kindTitle(kind)) · \(hint.label)"
        case .inBreak(let kind, let remaining, _):
            return "\(Self.kindTitle(kind)) · \(TGFormat.clock(remaining)) left"
        case .paused(let reasons, let kind, let remaining):
            let reason = StatusPresentation.primaryReason(reasons)
            let suffix = reason.map { reason -> String in
                if case .manual = reason { return "" }
                return " · \(reason.shortLabel)"
            } ?? ""
            return "Paused\(suffix) · \(Self.kindTitle(kind)) in \(TGFormat.menuBar(remaining))"
        }
    }

    private static func kindTitle(_ kind: BreakKind) -> String {
        kind == .long ? "Long break" : "Short break"
    }

    private func breakLength(_ kind: BreakKind) -> TimeInterval {
        let settings = settingsStore.settings
        return kind == .long ? settings.longBreakDuration : settings.shortBreakDuration
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

    private func addSubmenu(
        to menu: NSMenu,
        _ title: String,
        enabled: Bool,
        _ build: (NSMenu) -> Void
    ) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = enabled
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        build(submenu)
        for child in submenu.items where child.isSeparatorItem == false {
            child.isEnabled = enabled
        }
        item.submenu = submenu
        menu.addItem(item)
    }

    // MARK: - Commands

    /// The one place engine commands are issued. Every closure here runs from a user action.
    private func makeActions() -> MenuBarActions {
        MenuBarActions(
            startBreak: { [weak self] kind in self?.engine.startBreakNow(kind) },
            startCustomBreak: { [weak self] seconds in self?.engine.startCustomBreak(duration: seconds) },
            delay: { [weak self] seconds in self?.delay(seconds) },
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

    /// "+5m". A snooze once the break is imminent (that's what spends the budget), plain added
    /// time before then — `BreakEngine.snooze` is a no-op while the timer is still mid-interval.
    private func delay(_ seconds: TimeInterval) {
        engine.canSnoozeNow ? engine.snooze(seconds) : engine.addTime(seconds)
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
            actions.delay(60)
        case .skipOrEndBreak:
            actions.skipOrEnd()
        case .openQuickPanel:
            quickPanel?.toggle(relativeTo: statusItem.button)
        }
    }

    // MARK: - Menu targets

    @objc private func menuStartThisBreak() {
        engine.startBreakNow(engine.nextBreakKind)
    }

    @objc private func menuDelay(_ sender: NSMenuItem) {
        guard let seconds = (sender.representedObject as? NSNumber)?.doubleValue else { return }
        delay(seconds)
    }

    @objc private func menuCustomBreak(_ sender: NSMenuItem) {
        guard let seconds = (sender.representedObject as? NSNumber)?.doubleValue else { return }
        engine.startCustomBreak(duration: seconds)
    }

    @objc private func menuResume() { engine.resumeManually() }

    @objc private func menuPause(_ sender: NSMenuItem) {
        engine.pauseManually(for: (sender.representedObject as? NSNumber)?.doubleValue)
    }

    @objc private func menuAbout() { showSettings(selecting: .about) }
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
