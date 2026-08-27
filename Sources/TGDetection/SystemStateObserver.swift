// TGDetection — lock / screensaver / sleep / session state.
//
// Lock and screensaver only come through DistributedNotificationCenter (and only with
// `.deliverImmediately`, otherwise a background app gets them coalesced or not at all). The initial
// state is seeded from `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]` because
// notifications only tell us about *transitions*.
import AppKit
import Combine
import CoreGraphics
import Foundation

// MARK: - Model

public struct SystemState: Sendable, Equatable {
    public var isLocked = false
    public var isScreensaverActive = false
    public var isDisplayAsleep = false
    public var isSystemAsleep = false
    public var isSessionActive = true
    public var lastWake: Date?
    public var lastUnlock: Date?

    /// The user demonstrably cannot see the screen.
    public var isUserAway: Bool {
        isLocked || isScreensaverActive || isDisplayAsleep || isSystemAsleep || !isSessionActive
    }

    public var summary: String {
        var flags: [String] = []
        if isLocked { flags.append("locked") }
        if isScreensaverActive { flags.append("screensaver") }
        if isDisplayAsleep { flags.append("displayAsleep") }
        if isSystemAsleep { flags.append("systemAsleep") }
        if !isSessionActive { flags.append("sessionInactive") }
        return flags.isEmpty ? "active" : flags.joined(separator: "+")
    }
}

// MARK: - Observer

@MainActor
public final class SystemStateObserver: ObservableObject {

    @Published public private(set) var state = SystemState()

    public var isLocked: Bool { state.isLocked }

    // Callbacks (used by ActivityMonitor) …
    public var onLock: (@MainActor () -> Void)?
    public var onUnlock: (@MainActor () -> Void)?
    public var onWake: (@MainActor () -> Void)?
    public var onSleep: (@MainActor () -> Void)?
    public var onChange: (@MainActor () -> Void)?

    // … and Combine publishers, for anyone who prefers them.
    public let lockChanges = PassthroughSubject<Bool, Never>()
    public let wakeEvents = PassthroughSubject<Date, Never>()
    public let sleepEvents = PassthroughSubject<Date, Never>()

    private var workspaceObservers: [NSObjectProtocol] = []
    private var isRunning = false

    public init() {}

    // MARK: Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        state.isLocked = Self.seedLockState()

        // Selector-based API only: it is the one that accepts `.deliverImmediately`, which a
        // background LSUIElement app needs or these notifications arrive coalesced — or never.
        let distributed = DistributedNotificationCenter.default()
        for name in Self.distributedNames {
            distributed.addObserver(self, selector: #selector(handleDistributed(_:)),
                                    name: Notification.Name(name), object: nil,
                                    suspensionBehavior: .deliverImmediately)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        func workspaceObserver(_ name: Notification.Name, _ handler: @escaping @MainActor () -> Void) {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            })
        }

        workspaceObserver(NSWorkspace.willSleepNotification) { [weak self] in self?.setSystemAsleep(true) }
        workspaceObserver(NSWorkspace.didWakeNotification) { [weak self] in self?.setSystemAsleep(false) }
        workspaceObserver(NSWorkspace.screensDidSleepNotification) { [weak self] in self?.setDisplayAsleep(true) }
        workspaceObserver(NSWorkspace.screensDidWakeNotification) { [weak self] in self?.setDisplayAsleep(false) }
        workspaceObserver(NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.setSessionActive(false) }
        workspaceObserver(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.setSessionActive(true) }

        onChange?()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        DistributedNotificationCenter.default().removeObserver(self)
        let workspace = NSWorkspace.shared.notificationCenter
        for o in workspaceObservers { workspace.removeObserver(o) }
        workspaceObservers.removeAll()
    }

    static let distributedNames = [
        "com.apple.screenIsLocked",
        "com.apple.screenIsUnlocked",
        "com.apple.screensaver.didstart",
        "com.apple.screensaver.didstop",
    ]

    @objc private func handleDistributed(_ notification: Notification) {
        MainActor.assumeIsolated {
            switch notification.name.rawValue {
            case "com.apple.screenIsLocked":        setLocked(true)
            case "com.apple.screenIsUnlocked":      setLocked(false)
            case "com.apple.screensaver.didstart":  setScreensaver(true)
            case "com.apple.screensaver.didstop":   setScreensaver(false)
            default:                                break
            }
        }
    }

    // MARK: Transitions

    private func setLocked(_ locked: Bool) {
        guard state.isLocked != locked else { return }
        state.isLocked = locked
        if !locked {
            state.lastUnlock = Date()
            onUnlock?()
            wakeEvents.send(Date())
            onWake?()
        } else {
            onLock?()
        }
        lockChanges.send(locked)
        onChange?()
    }

    private func setScreensaver(_ active: Bool) {
        guard state.isScreensaverActive != active else { return }
        state.isScreensaverActive = active
        if !active { onWake?(); wakeEvents.send(Date()) }
        onChange?()
    }

    private func setDisplayAsleep(_ asleep: Bool) {
        guard state.isDisplayAsleep != asleep else { return }
        state.isDisplayAsleep = asleep
        if asleep { onSleep?(); sleepEvents.send(Date()) } else { state.lastWake = Date(); onWake?(); wakeEvents.send(Date()) }
        onChange?()
    }

    private func setSystemAsleep(_ asleep: Bool) {
        guard state.isSystemAsleep != asleep else { return }
        state.isSystemAsleep = asleep
        if asleep {
            onSleep?()
            sleepEvents.send(Date())
        } else {
            state.lastWake = Date()
            // Notifications can arrive out of order across a sleep; re-seed from the window server.
            state.isLocked = Self.seedLockState()
            onWake?()
            wakeEvents.send(Date())
        }
        onChange?()
    }

    private func setSessionActive(_ active: Bool) {
        guard state.isSessionActive != active else { return }
        state.isSessionActive = active
        if active { onWake?(); wakeEvents.send(Date()) }
        onChange?()
    }

    // MARK: Seeding

    /// The only way to know whether the screen is *already* locked at launch.
    public static func seedLockState() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if let locked = session["CGSSessionScreenIsLocked"] as? Bool { return locked }
        if let locked = session["CGSSessionScreenIsLocked"] as? NSNumber { return locked.boolValue }
        return false
    }

    // MARK: Debug

    public func debugDescription() -> String {
        var line = "system: \(state.summary)"
        if let wake = state.lastWake {
            line += String(format: " lastWake=%.0fs ago", Date().timeIntervalSince(wake))
        }
        return line
    }
}
