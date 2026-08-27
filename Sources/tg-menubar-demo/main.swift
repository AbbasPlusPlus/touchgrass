// tg-menubar-demo — boots just the TGMenuBar surfaces so they can be run and looked at.
//
//   swift run tg-menubar-demo            # status item only
//   swift run tg-menubar-demo panel      # + quick panel
//   swift run tg-menubar-demo settings   # + settings window
//   swift run tg-menubar-demo onboarding # + first-run flow
//
// Set TG_SNAPSHOT=<dir> to render every visible window to a PNG and quit — `screencapture`
// needs Screen Recording permission, drawing our own view hierarchy doesn't.
//
// The BreakEngine is constructed but never driven: its methods are unimplemented in this
// worktree, so this demo only ever reads `phase` (which starts at `.stopped`).
import AppKit
import TGCore
import TGMenuBar

@MainActor
final class DemoDelegate: NSObject, NSApplicationDelegate {

    private var store: SettingsStore!
    private var engine: BreakEngine!
    private var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the demo's settings out of the real app's file.
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TouchGrass", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        store = SettingsStore(url: directory.appendingPathComponent("settings-demo.json"))
        engine = BreakEngine(settings: store.settings)
        statusBar = StatusBarController(
            engine: engine,
            settingsStore: store,
            previewSound: { style, event in
                NSLog("[demo] preview sound: %@ / %@", style.rawValue, event)
            },
            onQuit: { NSApp.terminate(nil) },
            onStartStop: { NSLog("[demo] start/stop (the engine isn't driven in the demo)") }
        )

        let surface = CommandLine.arguments.dropFirst().first
        open(surface)

        if let output = ProcessInfo.processInfo.environment["TG_SNAPSHOT"] {
            scheduleSnapshots(of: surface, into: output)
        }
    }

    // MARK: - Surfaces

    private func open(_ surface: String?) {
        switch surface {
        case "settings":
            statusBar.showSettings()
        case "onboarding":
            statusBar.showOnboarding()
        case "panel":
            // Give the status item a run-loop turn to land in the menu bar first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.statusBar.showQuickPanel()
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
            guard let view = window.contentView else { continue }
            let bounds = view.bounds
            guard bounds.width > 40, bounds.height > 40,
                  let content = view.bitmapImageRepForCachingDisplay(in: bounds),
                  let canvas = view.bitmapImageRepForCachingDisplay(in: bounds),
                  let context = NSGraphicsContext(bitmapImageRep: canvas) else { continue }

            // Offscreen drawing defaults to Aqua and leaves unbacked regions clear, so render
            // under the window's real appearance and composite over the window background.
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                view.cacheDisplay(in: bounds, to: content)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                NSColor.windowBackgroundColor.setFill()
                bounds.fill()
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

    /// Blows the 18 pt status item glyph up so its shape can actually be judged.
    /// It's a black template image, so a light backdrop shows it the way a light menu bar would.
    private static func snapshotStatusIcon(into directory: String) {
        let scale: CGFloat = 8
        let side = StatusBarIcon.size * scale
        let rect = NSRect(x: 0, y: 0, width: side, height: side)

        for (name, dimmed) in [("icon", false), ("icon-dimmed", true)] {
            let image = NSImage(size: NSSize(width: side, height: side))
            image.lockFocus()
            NSColor.white.setFill()
            rect.fill()
            StatusBarIcon.grass(dimmed: dimmed)
                .draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            image.unlockFocus()

            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let data = rep.representation(using: .png, properties: [:]) else { continue }
            let url = URL(fileURLWithPath: directory).appendingPathComponent("tg-\(name).png")
            try? data.write(to: url)
            NSLog("[demo] wrote %@", url.path)
        }
    }
}

/// `main.swift` top-level code is not main-actor isolated in Swift 5 mode, but it does run on
/// the main thread — so assert that once and do the AppKit work inside.
@MainActor
private enum Demo {
    /// NSApplication holds its delegate weakly; this keeps it alive.
    static let delegate = DemoDelegate()

    static func run() -> Never {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        exit(0)
    }
}

MainActor.assumeIsolated { Demo.run() }
