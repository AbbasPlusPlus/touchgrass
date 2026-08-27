import AppKit
import TGCore
import TGDetection
import TGAudio
import TGOverlay
import TGMenuBar

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: SettingsStore!
    var engine: BreakEngine!
    var monitor: ActivityMonitor!
    var overlay: OverlayCoordinator!
    var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = SettingsStore()
        engine = BreakEngine(settings: store.settings)
        monitor = ActivityMonitor(settings: store.settings)
        overlay = OverlayCoordinator(engine: engine, settingsStore: store)
        statusBar = StatusBarController(engine: engine, settingsStore: store)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
