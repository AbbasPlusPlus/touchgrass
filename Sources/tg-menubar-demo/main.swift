// tg-menubar-demo — boots just the TGMenuBar surfaces so they can be run and looked at.
//
//   swift run tg-menubar-demo            # status item only
//   swift run tg-menubar-demo panel      # + quick panel (Now)
//   swift run tg-menubar-demo stats      # + quick panel (Stats), seeded with a fake month
//   swift run tg-menubar-demo calendar   # + quick panel (Stats → month grid)
//   swift run tg-menubar-demo settings   # + settings window
//   swift run tg-menubar-demo onboarding # + first-run flow
//
// Set TG_SNAPSHOT=<dir> to render every visible window to a PNG and quit — `screencapture`
// needs Screen Recording permission, drawing our own view hierarchy doesn't.
//
// The engine is started and ticked once a second, so the quick panel and the status item
// show a real countdown rather than the `.stopped` placeholder.
import AppKit
import TGCore
import TGMenuBar
import TGAssets

@MainActor
final class DemoDelegate: NSObject, NSApplicationDelegate {

    private var store: SettingsStore!
    private var stats: StatsStore!
    private var engine: BreakEngine!
    private var statusBar: StatusBarController!
    private var ticker: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.forceAppearance()

        // Keep the demo's settings out of the real app's file.
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TouchGrass", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        store = SettingsStore(url: directory.appendingPathComponent("settings-demo.json"))
        stats = StatsStore(
            settings: store.settings,
            url: directory.appendingPathComponent("stats-demo.json")
        )
        DemoStats.seed(into: stats)

        // TG_DEMO_WELLNESS=<seconds> fakes a pending blink nudge so the panel's wellness fact
        // can be reviewed; the demo doesn't run a real WellnessScheduler.
        let wellnessSeconds = Double(ProcessInfo.processInfo.environment["TG_DEMO_WELLNESS"] ?? "")
        if wellnessSeconds != nil { store.settings.blinkRemindersEnabled = true }

        engine = BreakEngine(settings: store.settings)
        statusBar = StatusBarController(
            engine: engine,
            settingsStore: store,
            statsStore: stats,
            previewSound: { style, event in
                NSLog("[demo] preview sound: %@ / %@", style.rawValue, event)
            },
            onQuit: { NSApp.terminate(nil) },
            wellnessCountdown: { wellnessSeconds }
        )

        // Wall-clock ticks, like the real app: the engine reads `Date`, the timer only tells
        // it when to look.
        engine.start()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { self.engine.tick() }
        }
        applyDemoState(ProcessInfo.processInfo.environment["TG_DEMO_STATE"])

        let surface = CommandLine.arguments.dropFirst().first
        open(surface)

        if let output = ProcessInfo.processInfo.environment["TG_SNAPSHOT"] {
            scheduleSnapshots(of: surface, into: output)
        }
    }

    /// `TG_APPEARANCE=light|dark` pins the demo to one appearance so both can be reviewed
    /// without touching the machine's own System Settings.
    private static func forceAppearance() {
        switch ProcessInfo.processInfo.environment["TG_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      break
        }
    }

    // MARK: - States

    /// `TG_DEMO_STATE=meeting|paused|break|stopped` puts the engine into a state the demo would
    /// otherwise take twenty minutes to reach, so every face of the quick panel can be reviewed.
    private func applyDemoState(_ state: String?) {
        switch state {
        case "meeting":
            engine.updatePauseReasons([.meeting(appName: "Zoom", bundleID: "us.zoom.xos")])
        case "paused":
            engine.pauseManually(for: nil)
        case "break":
            engine.startBreakNow(.short)
        case "stopped":
            engine.stop()
        default:
            break
        }
    }

    // MARK: - Surfaces

    private func open(_ surface: String?) {
        switch surface {
        case "settings":
            statusBar.showSettings()
        case "onboarding":
            statusBar.showOnboarding()
        case "panel", "stats", "calendar":
            let tab: QuickPanelTab = surface == "panel" ? .now : .stats
            let calendar = surface == "calendar"
            // Give the status item a run-loop turn to land in the menu bar first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.statusBar.showQuickPanel(selecting: tab, showingCalendar: calendar)
            }
        default:
            break
        }
    }

    // MARK: - Snapshots

    /// For the settings window, walk every page so a whole design pass can be reviewed at once.
    private func scheduleSnapshots(of surface: String?, into directory: String) {
        var delay = 1.2
        if surface == "settings" {
            for section in SettingsSection.allCases {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.statusBar.showSettings(selecting: section)
                }
                delay += 0.35
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    Self.snapshotVisibleWindows(into: directory, suffix: section.rawValue)
                }
                delay += 0.35
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Self.snapshotVisibleWindows(into: directory, suffix: surface ?? "statusitem")
            }
            delay += 0.5
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Self.snapshotStatusIcon(into: directory)
            NSApp.terminate(nil)
        }
    }

    private static func snapshotVisibleWindows(into directory: String, suffix: String) {
        for window in NSApp.windows where window.isVisible {
            // TG_SNAPSHOT_SIZE=900x1200 grows resizable windows so a long page fits in one image.
            if let size = ProcessInfo.processInfo.environment["TG_SNAPSHOT_SIZE"],
               window.styleMask.contains(.resizable) {
                let parts = size.split(separator: "x").compactMap { Double($0) }
                if parts.count == 2 {
                    window.setContentSize(NSSize(width: parts[0], height: parts[1]))
                    window.displayIfNeeded()
                }
            }
            guard let contentView = window.contentView else { continue }

            // `NSGlassEffectView` composites on the window server and caches as blank, so a
            // glass-backed panel would snapshot empty. When the content view isn't itself the
            // SwiftUI host, reach past the material and draw the host over a stand-in.
            let host = hostingView(in: contentView)
            let usesMaterialStandIn = host != nil && host !== contentView
            let view = usesMaterialStandIn ? (host ?? contentView) : contentView
            let bounds = view.bounds
            guard bounds.width > 40, bounds.height > 40,
                  let content = view.bitmapImageRepForCachingDisplay(in: bounds),
                  let canvas = view.bitmapImageRepForCachingDisplay(in: bounds),
                  let context = NSGraphicsContext(bitmapImageRep: canvas) else { continue }

            // Offscreen drawing defaults to Aqua and leaves unbacked regions clear, so render
            // under the window's real appearance and composite over the window background.
            //
            // Transparent windows (onboarding, the quick panel) are the exception: there the
            // content view's own rounded shape *is* the window, so filling a square backdrop
            // would invent a squared-off edge the user never sees. Keep those on alpha.
            // A transparent window whose content view is the SwiftUI host draws its own
            // shape; anything else needs an opaque backdrop to be legible.
            let isTransparent = !window.isOpaque && !usesMaterialStandIn
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                view.cacheDisplay(in: bounds, to: content)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                if isTransparent {
                    NSColor.clear.setFill()
                    bounds.fill(using: .copy)
                } else {
                    // A stand-in for whatever the panel is floating over. Picked off the
                    // window's own appearance rather than `windowBackgroundColor`, which
                    // resolves against the *drawing* appearance and can disagree with what
                    // SwiftUI just rendered.
                    Self.standInBackdrop(for: window).setFill()
                    bounds.fill()
                }
                content.draw(in: bounds)
                NSGraphicsContext.restoreGraphicsState()
            }

            guard let data = canvas.representation(using: .png, properties: [:]) else { continue }
            let url = URL(fileURLWithPath: directory)
                .appendingPathComponent("tg-\(suffix).png")
            try? data.write(to: url)
            NSLog("[demo] wrote %@", url.path)
        }
    }

    /// The neutral "desktop" a glass surface is composited over in a snapshot.
    private static func standInBackdrop(for window: NSWindow) -> NSColor {
        let dark = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(calibratedWhite: dark ? 0.15 : 0.86, alpha: 1)
    }

    /// Depth-first search for the SwiftUI host inside a window's view tree.
    private static func hostingView(in view: NSView) -> NSView? {
        if String(describing: type(of: view)).hasPrefix("NSHostingView") { return view }
        for subview in view.subviews {
            if let found = hostingView(in: subview) { return found }
        }
        return nil
    }

    /// Rasterises the status item glyph at its *real* pixel sizes (18 pt @1x and @2x) and then
    /// blows each up with nearest-neighbour, so what you look at is exactly the pixels the menu
    /// bar gets — drawing the vector straight into a big rect would flatter it.
    private static func snapshotStatusIcon(into directory: String) {
        for (name, dimmed) in [("icon", false), ("icon-dimmed", true)] {
            for (suffix, pixels) in [("", 18), ("@2x", 36)] {
                guard let small = rasterise(StatusBarIcon.grass(dimmed: dimmed), pixels: pixels),
                      let big = magnify(small, by: 12)
                else { continue }
                let url = URL(fileURLWithPath: directory)
                    .appendingPathComponent("tg-\(name)\(suffix).png")
                if let data = big.representation(using: .png, properties: [:]) {
                    try? data.write(to: url)
                    NSLog("[demo] wrote %@", url.path)
                }
            }
        }
    }

    /// Draws `image` into a bitmap of exactly `pixels` square.
    private static func rasterise(_ image: NSImage, pixels: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Nearest-neighbour upscale over a light backdrop, the way a light menu bar would show it.
    private static func magnify(_ rep: NSBitmapImageRep, by factor: Int) -> NSBitmapImageRep? {
        let side = rep.pixelsWide * factor
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: out)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .none
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        rep.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                 from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: true, hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)])
        NSGraphicsContext.restoreGraphicsState()
        return out
    }
}

/// `main.swift` top-level code is not main-actor isolated in Swift 5 mode, but it does run on
/// the main thread — so assert that once and do the AppKit work inside.
@MainActor
private enum Demo {
    /// NSApplication holds its delegate weakly; this keeps it alive.
    static let delegate = DemoDelegate()

    static func run() -> Never {
        // Writes the status-bar icon variants to /tmp for visual verification, then exits.
if CommandLine.arguments.contains("icon-dump") {
    for (name, dimmed) in [("normal", false), ("dimmed", true)] {
        let img = StatusBarIcon.grass(dimmed: dimmed)
        let big = NSImage(size: NSSize(width: 144, height: 144), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            img.isTemplate = false
            img.draw(in: rect.insetBy(dx: 12, dy: 12))
            return true
        }
        if let tiff = big.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "/tmp/tg-icon-\(name).png"))
        }
    }
    exit(0)
}

let app = { TGAssets.registerFonts(); return NSApplication.shared }()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // Dev harness safety: a forgotten demo process leaves a ghost status item in the menu bar.
let lifetime = Double(ProcessInfo.processInfo.environment["TG_DEMO_LIFETIME"] ?? "") ?? 300
DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { NSApp.terminate(nil) }
app.run()
        exit(0)
    }
}

MainActor.assumeIsolated { Demo.run() }
