// TGDetection — user-declared "deep focus" apps (Xcode, Figma, a game…).
// `Settings.deepFocusApps` × `Settings.deepFocusMode` decides how strict the trigger is.
import AppKit
import Foundation
import TGCore

@MainActor
public final class DeepFocusDetector {

    public private(set) var reason: PauseReason?
    /// Which app satisfied the rule, for debug output.
    public private(set) var matched: RunningAppInfo?

    public var settings: Settings {
        didSet {
            guard settings.deepFocusApps != oldValue.deepFocusApps
                    || settings.deepFocusMode != oldValue.deepFocusMode else { return }
            syncPoll()
            refresh()
        }
    }
    public var onChange: (@MainActor () -> Void)?

    /// Supplied by ActivityMonitor so the two detectors stay independent.
    private let isFullscreen: @MainActor (String) -> Bool
    private var poll: PollTimer?
    private var isRunning = false
    private var observers: [NSObjectProtocol] = []

    public init(settings: Settings, isFullscreen: @escaping @MainActor (String) -> Bool) {
        self.settings = settings
        self.isFullscreen = isFullscreen
    }

    // MARK: Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        syncPoll()
        refresh()
    }

    /// The notifications alone cover launch/quit/activation; the poll only exists to catch an app
    /// entering fullscreen in place. With no deep-focus apps configured there is nothing to watch,
    /// so no timer is created at all.
    private func syncPoll() {
        let wanted = isRunning && !settings.deepFocusApps.isEmpty
            && settings.deepFocusMode == .foregroundAndFullscreen
        if wanted, poll == nil {
            let timer = PollTimer(interval: 5) { [weak self] in self?.refresh() }
            poll = timer
            timer.start()
        } else if !wanted {
            poll?.stop()
            poll = nil
        }
    }

    public func stop() {
        isRunning = false
        poll?.stop()
        poll = nil
        let center = NSWorkspace.shared.notificationCenter
        for o in observers { center.removeObserver(o) }
        observers.removeAll()
        reason = nil
        matched = nil
    }

    // MARK: Reading

    public func refresh() {
        let candidates = FrontmostAppProbe.runningApps(matching: settings.deepFocusApps)
        var hit: RunningAppInfo?

        if !candidates.isEmpty {
            switch settings.deepFocusMode {
            case .open:
                hit = candidates.first
            case .foreground:
                hit = candidates.first { FrontmostAppProbe.isFrontmost(pid: $0.pid) }
            case .foregroundAndFullscreen:
                hit = candidates.first {
                    guard FrontmostAppProbe.isFrontmost(pid: $0.pid), let b = $0.bundleID else { return false }
                    return isFullscreen(b)
                }
            }
        }

        let newReason: PauseReason? = hit.map { .deepFocusApp(appName: $0.display, bundleID: $0.bundleID) }
        let changed = newReason != reason
        matched = hit
        reason = newReason
        if changed { onChange?() }
    }

    // MARK: Debug

    public func debugDescription() -> String {
        if settings.deepFocusApps.isEmpty { return "deepFocus: (no apps configured)" }
        return "deepFocus: mode=\(settings.deepFocusMode.rawValue) apps=\(settings.deepFocusApps) "
            + "matched=\(matched?.display ?? "nil")"
    }
}
