// TGDetection — "is the frontmost app filling a whole display?".
//
// `CGWindowListCopyWindowInfo` metadata (owner pid, layer, bounds, onscreen flag) is free and needs no
// Screen Recording permission — only `kCGWindowName` is withheld, and we don't want it. A window is
// treated as fullscreen when it is layer 0, onscreen, owned by the frontmost app, and its bounds match
// some display's `CGDisplayBounds` within ±40 pt. `CGSGetActiveSpace` is broken on macOS 26, and
// `NSScreen.visibleFrame` is per-process and does NOT change when another app goes fullscreen
// (measured), so neither is used.
//
// Measured here (1800x1169 display with a notch, Dock auto-hidden): native fullscreen and a merely
// maximised window have IDENTICAL layer-0 bounds, `0,39 1800x1130` — which is why the ±40 pt slack is
// needed at all. What separates them is the menu bar:
//     fullscreen   layer 26 @ 0,0 1800x39   ← the app's own auto-hiding menu-bar overlay
//                  layer  0 @ 0,39 1800x1130
//     maximised    layer  0 @ 0,39 1800x1130   ← and nothing above layer 0
// So a window inset by the menu-bar strip must additionally own that overlay to count.
import AppKit
import CoreGraphics
import Foundation
import TGCore

// MARK: - Model

public struct FullscreenWindowInfo: Sendable, Hashable {
    public let pid: pid_t
    public let appName: String
    public let bundleID: String?
    public let windowBounds: CGRect
    public let displayBounds: CGRect
}

// MARK: - Detector

@MainActor
public final class FullscreenDetector {

    public private(set) var frontmost: RunningAppInfo?
    public private(set) var fullscreen: FullscreenWindowInfo?
    /// `.fullscreenApp(appName:bundleID:)` when enabled in settings and something is fullscreen.
    public private(set) var reason: PauseReason?

    public var settings: Settings {
        didSet { if settings.pauseOnFullscreen != oldValue.pauseOnFullscreen { refresh() } }
    }
    public var onChange: (@MainActor () -> Void)?

    private var poll: PollTimer?
    private var observers: [NSObjectProtocol] = []
    private let coalescer = OneShotTimer()
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    public init(settings: Settings) {
        self.settings = settings
    }

    // MARK: Lifecycle

    public func start() {
        guard poll == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            })
        }
        // The activation notification covers most transitions; the poll catches an app that goes
        // fullscreen without ever changing frontmost (Cmd-Ctrl-F, video going fullscreen in place).
        let timer = PollTimer(interval: 5) { [weak self] in self?.refresh() }
        poll = timer
        timer.start()
        refresh()
    }

    public func stop() {
        poll?.stop()
        poll = nil
        coalescer.cancel()
        let center = NSWorkspace.shared.notificationCenter
        for o in observers { center.removeObserver(o) }
        observers.removeAll()
        frontmost = nil
        fullscreen = nil
        reason = nil
    }

    private func scheduleRefresh() {
        // App activation animations settle in ~200 ms; reading window bounds sooner sees the old frame.
        coalescer.schedule(after: 0.35) { [weak self] in self?.refresh() }
    }

    // MARK: Reading

    public func refresh() {
        let front = FrontmostAppProbe.frontmost()
        let found = front.flatMap { fullscreenWindow(forPID: $0.pid, app: $0) }
        let newReason: PauseReason? = (settings.pauseOnFullscreen && found != nil)
            ? .fullscreenApp(appName: found?.appName ?? "App", bundleID: found?.bundleID)
            : nil

        let changed = front != frontmost || found != fullscreen || newReason != reason
        frontmost = front
        fullscreen = found
        reason = newReason
        if changed { onChange?() }
    }

    /// True when `bundleID`'s window is the fullscreen one (used by deep-focus mode).
    public func isFullscreen(bundleID: String) -> Bool {
        guard let fullscreen, let b = fullscreen.bundleID else { return false }
        return BundleMatch.matches(b, entry: bundleID)
    }

    private func fullscreenWindow(forPID pid: pid_t, app: RunningAppInfo) -> FullscreenWindowInfo? {
        guard pid != ownPID else { return nil }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        let displays = FullscreenGeometry.displayBounds()

        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  (window[kCGWindowIsOnscreen as String] as? Bool) ?? true,
                  let bounds = FullscreenGeometry.bounds(of: window) else { continue }

            guard let display = displays.first(where: { FullscreenGeometry.isApproximately(bounds, $0) }) else { continue }

            // Inset by exactly the menu-bar strip? Then it is only fullscreen if the app owns the
            // auto-hiding menu-bar overlay; otherwise it is a maximised window.
            let coversOrigin = abs(bounds.origin.y - display.origin.y) <= FullscreenGeometry.originTolerance
            guard coversOrigin || FullscreenGeometry.ownsMenuBarOverlay(pid: pid, display: display, in: windows) else { continue }

            return FullscreenWindowInfo(
                pid: pid,
                appName: app.name ?? (window[kCGWindowOwnerName as String] as? String) ?? "App",
                bundleID: app.bundleID,
                windowBounds: bounds,
                displayBounds: display
            )
        }
        return nil
    }

    // MARK: Debug

    public func debugDescription() -> String {
        var lines = ["fullscreen: reason=\(reason.map { "\($0)" } ?? "nil")"]
        lines.append("  frontmost=\(frontmost?.display ?? "nil") bundle=\(frontmost?.bundleID ?? "nil")")
        if let f = fullscreen {
            lines.append("  window=\(FullscreenGeometry.describe(f.windowBounds)) display=\(FullscreenGeometry.describe(f.displayBounds))")
        } else {
            lines.append("  no fullscreen window (displays: "
                         + FullscreenGeometry.displayBounds().map(FullscreenGeometry.describe).joined(separator: ", ") + ")")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Geometry

/// Pure window/display geometry. Deliberately not actor-isolated: no state, and unit-testable.
public enum FullscreenGeometry {

    /// Slack on the window *size*. A native fullscreen window is exactly the display, but HiDPI
    /// rounding and apps that inset by a hair need room. It is also what absorbs the menu-bar strip.
    public static let boundsTolerance: CGFloat = 40
    /// A window that starts *exactly* at the display origin is unambiguously fullscreen.
    public static let originTolerance: CGFloat = 8

    public static func isApproximately(_ window: CGRect, _ display: CGRect) -> Bool {
        let t = boundsTolerance
        return abs(window.origin.x - display.origin.x) <= t
            && abs(window.origin.y - display.origin.y) <= t
            && abs(window.width - display.width) <= t
            && abs(window.height - display.height) <= t
    }

    /// A fullscreen app owns a thin, display-wide window above layer 0 pinned to the display origin —
    /// the menu bar it took over. A merely maximised app owns no such window (measured). The Window
    /// Server owns a similar one at layer 24; that one is not the app's.
    public static func ownsMenuBarOverlay(pid: pid_t, display: CGRect, in windows: [[String: Any]]) -> Bool {
        windows.contains { window in
            guard let owner = window[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let layer = window[kCGWindowLayer as String] as? Int, layer > 0,
                  let bounds = bounds(of: window) else { return false }
            return abs(bounds.origin.x - display.origin.x) <= 2
                && abs(bounds.origin.y - display.origin.y) <= 2
                && abs(bounds.width - display.width) <= 2
                && bounds.height <= 80
        }
    }

    public static func bounds(of window: [String: Any]) -> CGRect? {
        guard let dict = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dict)
    }

    /// `CGDisplayBounds` is in the same top-left-origin global space as `kCGWindowBounds`.
    public static func displayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    static func describe(_ r: CGRect) -> String {
        String(format: "%.0f,%.0f %.0fx%.0f", r.origin.x, r.origin.y, r.width, r.height)
    }
}
