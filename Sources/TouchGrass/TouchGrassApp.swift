import AppKit
import Combine
import TGCore
import TGDetection
import TGAudio
import TGOverlay
import TGMenuBar

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: SettingsStore!
    private var stats: StatsStore!
    private var statsRecorder: StatsRecorder!
    private var engine: BreakEngine!
    private var wellness: WellnessScheduler!
    private var monitor: ActivityMonitor!
    private var sounds: SoundPlayer!
    private var overlay: OverlayCoordinator!
    private var statusBar: StatusBarController!

    private var tickTimer: Timer?
    private var activityToken: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = SettingsStore()
        stats = StatsStore(settings: store.settings)
        engine = BreakEngine(settings: store.settings)
        statsRecorder = StatsRecorder(engine: engine, store: stats)
        wellness = WellnessScheduler(settings: store.settings)
        monitor = ActivityMonitor(settings: store.settings)
        sounds = SoundPlayer()
        overlay = OverlayCoordinator(engine: engine, settingsStore: store)
        statusBar = StatusBarController(
            engine: engine,
            settingsStore: store,
            statsStore: stats,
            previewSound: { [weak self] style, eventName in
                guard let self else { return }
                let event = SoundEvent(rawValue: eventName) ?? .breakStart
                self.sounds.preview(style, event: event)
            },
            wellnessCountdown: { [weak self] in
                guard let w = self?.wellness else { return nil }
                return [w.nextBlinkIn, w.nextPostureIn].compactMap { $0 }.min()
            }
        )

        wireSettings()
        wireDetection()
        wireWellness()
        startTicking()

        sounds.preloadAll()
        monitor.start()
        engine.start()
        statsRecorder.start()
        wellness.start()
        statusBar.showOnboardingIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tickTimer?.invalidate()
        // Closes the open session and writes stats.json now rather than on the save debounce.
        statsRecorder.stop()
        monitor.stop()
        if let token = activityToken { ProcessInfo.processInfo.endActivity(token) }
    }

    // MARK: - Wiring

    /// Settings flow one way: store → engine / wellness / monitor.
    private func wireSettings() {
        store.$settings
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] s in
                guard let self else { return }
                self.engine.settings = s
                self.wellness.settings = s
                self.monitor.settings = s
                self.stats.settings = s
            }
            .store(in: &cancellables)
    }

    /// Detector signals → engine. The engine owns `.idle`/`.screenLocked`/`.manual` itself,
    /// so idle and lock state are fed through their dedicated entry points.
    private func wireDetection() {
        monitor.$pauseReasons
            .removeDuplicates()
            .sink { [weak self] reasons in
                self?.engine.updatePauseReasons(reasons.filter { $0 != .screenLocked && $0 != .idle })
            }
            .store(in: &cancellables)

        monitor.$activityHint
            .removeDuplicates()
            .sink { [weak self] hint in self?.engine.updateActivityHint(hint) }
            .store(in: &cancellables)

        monitor.$idleSeconds
            .sink { [weak self] s in self?.engine.updateIdleSeconds(s) }
            .store(in: &cancellables)

        monitor.system.onLock = { [weak self] in self?.engine.screenDidLock() }
        monitor.system.onUnlock = { [weak self] in self?.engine.screenDidUnlock() }
        monitor.system.onWake = { [weak self] in
            self?.engine.systemDidWake()
            self?.monitor.refreshAll()
        }

        // Arm typing/dragging detection only in the final stretch before a break.
        engine.$phase
            .map { phase -> Bool in
                switch phase {
                case .preBreak(_, let remaining): return remaining <= 15
                case .waitingForActivityToStop: return true
                default: return false
                }
            }
            .removeDuplicates()
            .sink { [weak self] armed in
                armed ? self?.monitor.armActivityHints() : self?.monitor.disarmActivityHints()
            }
            .store(in: &cancellables)
    }

    /// Wellness reminders ride on the engine's event stream so the overlay sees one source.
    private func wireWellness() {
        wellness.events
            .sink { [weak self] event in self?.engine.events.send(event) }
            .store(in: &cancellables)

        engine.events
            .sink { [weak self] event in
                if case .breakEnded(_, let completed) = event, completed {
                    self?.wellness.resetAfterBreak()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Heartbeat

    private func startTicking() {
        // Menu-bar apps are prime App Nap targets; keep the 1 Hz heartbeat honest.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Break timer"
        )
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.engine.tick()
                // After the engine, so the phase the recorder banks time against is current.
                self.statsRecorder.tick()
                self.wellness.tick(isInBreak: self.engine.phase.isInBreak)
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }
}

@main
enum TouchGrassMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
