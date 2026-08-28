// tg-overlay-demo — shows any TGOverlay surface on every display, without the engine.
//
//   tg-overlay-demo break [short|long] [seconds] [casual|balanced|hardcore]
//                         [blur|wallpaper|gradient:<name>|animated:<name>]
//   tg-overlay-demo card | notch | pill | blink | posture | custom [title] [symbol] | toast
//
// `notch` is the Dynamic-Island pre-break banner. It fuses to the physical notch, so to see it
// off a notched display set TG_FAKE_NOTCH=1 to draw a stand-in. The panel is sharingType=.none
// (kept out of screen recordings), so `screencapture` never shows it — use TG_SHOT for the
// in-process bitmap instead.
//
// The wellness nudges are the sprout + word stack; a custom reminder's title and symbol pick
// the sprout's motion:
//   tg-overlay-demo custom "Water" drop.fill          → droplet runs down the stem
//   tg-overlay-demo custom "Stretch" figure.cooldown  → the plant straightens and grows
//   tg-overlay-demo custom "Eye drops" eyedropper     → the leaves rustle
//
// Prints the frontmost application before and after presenting, so it is easy to verify that
// nothing here ever steals focus.

import AppKit
import TGCore
import TGOverlay
import AppKit
import TGAssets


@MainActor func dumpPanels(after: Double) {
    DispatchQueue.main.asyncAfter(deadline: .now() + after) {
        for w in NSApp.windows where w is OverlayPanel {
            print("PANEL level=\(w.level.rawValue) behavior=\(w.collectionBehavior.rawValue) key=\(w.isKeyWindow) visible=\(w.isVisible)")
        }
    }
}
// MARK: - Argument parsing

func parseBackground(_ raw: String?) -> BreakBackground {
    guard let raw else { return .wallpaper }
    if raw == "blur" { return .screenBlur }
    if raw == "wallpaper" { return .wallpaper }
    if raw.hasPrefix("gradient:") {
        let name = String(raw.dropFirst("gradient:".count))
        return .gradient(GradientPreset(rawValue: name) ?? .dusk)
    }
    if raw.hasPrefix("animated:") {
        let name = String(raw.dropFirst("animated:".count))
        return .animated(AnimatedPreset(rawValue: name) ?? .aurora)
    }
    return .wallpaper
}

func frontmostName() -> String {
    NSWorkspace.shared.frontmostApplication?.localizedName ?? "(none)"
}

// MARK: - Demo driver

@MainActor
final class DemoDelegate: NSObject, NSApplicationDelegate {

    private let args: [String]
    private let overlay = BreakOverlayController()
    private let card = PreBreakCard()
    private let pill = CursorPill()
    private let toast = ToastPanel()
    private let wellness = WellnessNudgeController()

    private var ticker: Timer?
    private var remaining: TimeInterval = 0
    private var frontmostBefore = ""
    private var activityToken: NSObjectProtocol?

    init(args: [String]) {
        self.args = args
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.forceAppearance()

        // The real app holds one of these too; without it App Nap throttles the overlay and any
        // CPU measurement taken here is meaningless.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical], reason: "overlay demo")
        frontmostBefore = frontmostName()
        print("frontmost before: \(frontmostBefore)")
        print("displays: \(NSScreen.screens.count)")

        switch args.first ?? "break" {
        case "break":    runBreak()
        case "card":     runCard()
        case "notch":    runCard(style: .notch)
        case "pill":     runPill()
        case "blink":    runWellness(.blink)
        case "posture":  runWellness(.posture)
        case "custom":   runCustomReminder()
        case "toast":    runToast()
        default:
            print("unknown surface: \(args.first ?? "")")
            exit(2)
        }

        if let path = ProcessInfo.processInfo.environment["TG_SHOT"] {
            let delay = Double(ProcessInfo.processInfo.environment["TG_SHOT_DELAY"] ?? "") ?? 3.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Self.snapshotAllWindows(to: path)
                NSApp.terminate(nil)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            let after = frontmostName()
            print("frontmost after:  \(after)")
            print(after == self.frontmostBefore ? "focus: UNCHANGED ✓" : "focus: CHANGED ✗")
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

    // MARK: Break

    private func runBreak() {
    dumpPanels(after: 2.5)
        let kind: BreakKind = args.count > 1 && args[1] == "long" ? .long : .short
        let seconds = TimeInterval(args.count > 2 ? (Double(args[2]) ?? 20) : 20)
        let enforcement = Enforcement(rawValue: args.count > 3 ? args[3] : "balanced") ?? .balanced
        let background = parseBackground(args.count > 4 ? args[4] : nil)

        var settings = Settings()
        settings.enforcement = enforcement
        settings.background = background
        settings.balancedSkipDelaySeconds = 5
        let env = ProcessInfo.processInfo.environment
        if env["TG_NOCLOCK"] != nil { settings.showClock = false }
        if env["TG_NOTEXT"] != nil { settings.showTitle = false; settings.showSubtitle = false }
        let snoozes = Int(env["TG_SNOOZES"] ?? "") ?? 2
        settings.allowEndBreakEarlyAfterFraction = 0.5

        overlay.model.onSkip = { [weak self] in print("→ skip"); self?.finish() }
        overlay.model.onSnooze = { [weak self] s in print("→ snooze \(Int(s))s"); self?.finish() }
        overlay.model.onEndEarly = { [weak self] in print("→ end early"); self?.finish() }

        overlay.model.beginBreak(kind: kind, total: seconds, settings: settings, snoozesRemaining: snoozes)
        overlay.show()
        remaining = seconds

        print("break: \(kind) \(Int(seconds))s \(enforcement.rawValue) \(background)")
        if let gap = Int(env["TG_ESC_TEST"] ?? "") { scheduleEscapeTest(gapMilliseconds: gap) }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.remaining -= 1
                if env["TG_STATIC"] == nil {
                    self.overlay.model.update(remaining: max(0, self.remaining), snoozesRemaining: snoozes)
                }
                if self.remaining <= 0 { print("→ completed"); self.finish() }
            }
        }
    }

    // MARK: Card

    private func runCard(style: PreBreakStyle = .card) {
        card.style = style
        card.onStart = { [weak self] in print("→ start now"); self?.finish() }
        card.onSnooze = { [weak self] s in print("→ snooze \(Int(s))s"); self?.finish() }
        // TG_VISIBLE=<seconds> holds the banner (and its countdown) for that long — handy for
        // eyeballing the notch style: `TG_VISIBLE=180 tg-overlay-demo notch`.
        let visible = TimeInterval(ProcessInfo.processInfo.environment["TG_VISIBLE"] ?? "") ?? 20
        remaining = visible
        card.show(kind: .short, secondsLeft: Int(visible), snoozesRemaining: 3, visibleSeconds: visible)
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.remaining -= 1
                self.card.update(secondsLeft: Int(self.remaining), snoozesRemaining: 3)
                if self.remaining <= 0 { self.finish() }
            }
        }
        quit(after: visible + 3)
    }

    // MARK: Pill

    private func runPill() {
        remaining = 10
        pill.show(symbol: "eye", text: "Starting break in 10")
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.remaining -= 1
                if self.remaining <= 3 {
                    self.pill.update(symbol: "keyboard", text: "Typing…")
                } else {
                    self.pill.update(symbol: "eye", text: "Starting break in \(Int(self.remaining))")
                }
                if self.remaining <= 0 { self.pill.hide(); self.finish() }
            }
        }
        quit(after: 12)
    }

    // MARK: Wellness

    private func runWellness(_ kind: WellnessKind) {
        wellness.show(kind, dimsScreen: true, mainScreenOnly: false)
        quit(after: 5)
    }

    /// `tg-overlay-demo custom "Drink water" drop.fill`
    private func runCustomReminder() {
        let arguments = Array(CommandLine.arguments.dropFirst(2))
        wellness.showCustom(title: arguments.first ?? "Drink water",
                            symbol: arguments.dropFirst().first ?? "drop.fill",
                            dimsScreen: true,
                            mainScreenOnly: false)
        quit(after: 5)
    }

    // MARK: Toast

    private func runToast() {
        toast.show(symbol: "clock.arrow.circlepath",
                   text: "Timer reset — you were away 7 minutes",
                   undoTitle: "Undo",
                   undo: { print("→ undo") },
                   duration: 4)
        quit(after: 6)
    }

    // MARK: Self-tests

    /// Posts Escape key-downs to our own process so the double-Escape monitor can be exercised
    /// without Accessibility permission. `TG_ESC_TEST=<gap in ms>`.
    private func scheduleEscapeTest(gapMilliseconds: Int) {
        func esc() {
            // Synthetic CGEvents are filtered without Input Monitoring, so post a real NSEvent into
            // our own queue: that is exactly the path addLocalMonitorForEvents observes.
            guard let event = NSEvent.keyEvent(with: .keyDown,
                                               location: .zero,
                                               modifierFlags: [],
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: NSApp.keyWindow?.windowNumber ?? 0,
                                               context: nil,
                                               characters: "\u{1B}",
                                               charactersIgnoringModifiers: "\u{1B}",
                                               isARepeat: false,
                                               keyCode: 53)
            else { print("esc-test: could not synthesize"); return }
            NSApp.postEvent(event, atStart: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            print("keyWindow=\(String(describing: NSApp.keyWindow)) windows=\(NSApp.windows.count) active=\(NSApp.isActive)")
            print("esc-test: first Escape")
            esc()
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(gapMilliseconds) / 1000.0) {
                print("esc-test: second Escape (gap \(gapMilliseconds) ms)")
                esc()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    print("esc-test: no action fired")
                    NSApp.terminate(nil)
                }
            }
        }
    }

    // MARK: Snapshot (in-process; no Screen Recording permission needed)

    static func snapshotAllWindows(to path: String) {
        let base = (path as NSString).deletingPathExtension
        var index = 0
        for window in NSApp.windows where window.isVisible {
            guard let view = window.contentView, view.bounds.width > 1 else { continue }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            let out = index == 0 ? path : "\(base)-\(index).png"
            try? data.write(to: URL(fileURLWithPath: out))
            print("shot: \(out) \(Int(view.bounds.width))x\(Int(view.bounds.height))")
            index += 1
        }
    }

    // MARK: Exit

    private func finish() {
        ticker?.invalidate()
        ticker = nil
        overlay.hide { NSApp.terminate(nil) }
        pill.hide()
        card.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { NSApp.terminate(nil) }
    }

    private func quit(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
    }
}

// MARK: - Entry

var retainedDelegate: DemoDelegate?          // NSApplication.delegate is weak

MainActor.assumeIsolated {
    let app = { TGAssets.registerFonts(); return NSApplication.shared }()
    app.setActivationPolicy(.accessory)      // no Dock icon, no activation
    let delegate = DemoDelegate(args: Array(CommandLine.arguments.dropFirst()))
    retainedDelegate = delegate
    app.delegate = delegate
    app.run()
}
