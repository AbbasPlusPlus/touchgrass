// TGDetection — video playback via IOKit power assertions.
//
// Anything playing video holds a display-sleep assertion: Safari/Chrome ("Video Wake Lock"),
// QuickTime, IINA, Netflix, Music ("com.apple.Music.playback"). `IOPMCopyAssertionsByProcess` gives
// us the holder's pid, which `NSRunningApplication` turns into an app. ✔ No permission, identical in
// the sandbox. `IOPMCopyAssertionsStatus` is the cheap gate: when the aggregate count for both
// display types is 0, we skip the per-process copy entirely.
import AppKit
import Foundation
import IOKit.pwr_mgt
import TGCore

// MARK: - Model

public struct DisplayAssertionInfo: Sendable, Hashable {
    public let pid: pid_t
    public let processName: String?
    public let assertionType: String
    public let assertionName: String?
    public let appName: String?
    public let bundleID: String?
    public let isFrontmost: Bool
    /// Why this assertion did not become a `.video` pause (nil = it did count).
    public let ignoredReason: String?

    public var counts: Bool { ignoredReason == nil }
    public var display: String { appName ?? processName ?? "pid \(pid)" }
}

// MARK: - Detector

@MainActor
public final class VideoDetector {

    /// Assertion types that mean "keep the *display* awake". `UserIsActive` and
    /// `InternalPreventDisplaySleep` are noise and deliberately not here.
    static let displayAssertionTypes: Set<String> = [
        "PreventUserIdleDisplaySleep",   // kIOPMAssertionTypePreventUserIdleDisplaySleep
        "NoDisplaySleepAssertion",       // kIOPMAssertionTypeNoDisplaySleep
    ]

    /// Every display-sleep assertion seen on the last poll, including the ignored ones (debug output).
    public private(set) var assertions: [DisplayAssertionInfo] = []
    /// `.video(appName:bundleID:)` while a non-denylisted app holds one.
    public private(set) var reason: PauseReason?

    public var settings: Settings {
        didSet { if settings.videoExcludedApps != oldValue.videoExcludedApps
                    || settings.videoFrontmostOnly != oldValue.videoFrontmostOnly
                    || settings.pauseOnVideo != oldValue.pauseOnVideo { refresh() } }
    }
    public var onChange: (@MainActor () -> Void)?

    /// Power assertions have no notification API — research recommends 2–5 s.
    private let pollInterval: TimeInterval = 3
    private var poll: PollTimer?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    public init(settings: Settings) {
        self.settings = settings
    }

    // MARK: Lifecycle

    public func start() {
        guard poll == nil else { return }
        let timer = PollTimer(interval: pollInterval) { [weak self] in self?.refresh() }
        poll = timer
        timer.start()
        refresh()
    }

    public func stop() {
        poll?.stop()
        poll = nil
        assertions = []
        reason = nil
    }

    // MARK: Reading

    public func refresh() {
        let found = Self.anyDisplayAssertionsHeld() ? readAssertions() : []
        let counting = found.filter(\.counts)
        let newReason: PauseReason? = (settings.pauseOnVideo && !counting.isEmpty)
            ? .video(appName: counting[0].appName, bundleID: counting[0].bundleID)
            : nil

        let changed = found != assertions || newReason != reason
        assertions = found
        reason = newReason
        if changed { onChange?() }
    }

    private func readAssertions() -> [DisplayAssertionInfo] {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byProcess = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }

        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let resolver = ProcessAppResolver.shared
        var result: [DisplayAssertionInfo] = []

        for (pidNumber, list) in byProcess {
            let pid = pid_t(truncating: pidNumber)
            for entry in list {
                guard let type = entry["AssertType"] as? String, Self.displayAssertionTypes.contains(type) else { continue }
                let processName = entry["Process Name"] as? String
                let assertionName = entry["AssertName"] as? String
                let identity = resolver.identity(for: pid)
                let bundleID = identity.bundleID
                let appName = identity.name ?? processName
                let isFrontmost = frontPID == pid || (bundleID != nil && frontmostBundleMatches(bundleID))

                var ignored: String?
                if pid == ownPID {
                    ignored = "our own assertion"
                } else if KnownBundles.isCaffeinator(bundleID: bundleID, processName: processName ?? identity.processName) {
                    ignored = "caffeinator denylist"
                } else if BundleMatch.matches(bundleID, anyOf: settings.videoExcludedApps) {
                    ignored = "videoExcludedApps"
                } else if settings.videoFrontmostOnly && !isFrontmost {
                    ignored = "not frontmost"
                }

                result.append(DisplayAssertionInfo(
                    pid: pid, processName: processName, assertionType: type, assertionName: assertionName,
                    appName: appName, bundleID: bundleID, isFrontmost: isFrontmost, ignoredReason: ignored
                ))
            }
        }
        return result.sorted { ($0.pid, $0.assertionType) < ($1.pid, $1.assertionType) }
    }

    private func frontmostBundleMatches(_ bundleID: String?) -> Bool {
        guard let bundleID, let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return BundleMatch.matches(front, entry: bundleID) || BundleMatch.matches(bundleID, entry: front)
    }

    /// Cheap pre-check so the common case (nothing playing) costs one IOKit call.
    static func anyDisplayAssertionsHeld() -> Bool {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&raw) == kIOReturnSuccess,
              let status = raw?.takeRetainedValue() as? [String: Int] else { return true }  // unknown → look anyway
        return displayAssertionTypes.contains { (status[$0] ?? 0) > 0 }
    }

    // MARK: Debug

    public func debugDescription() -> String {
        var lines = ["video: reason=\(reason.map { "\($0)" } ?? "nil") displayAssertions=\(assertions.count)"
                     + " (frontmostOnly=\(settings.videoFrontmostOnly))"]
        for a in assertions {
            let verdict = a.ignoredReason.map { "ignored: \($0)" } ?? "COUNTS"
            lines.append("  · \(a.display) [\(a.assertionType)] name=\(a.assertionName ?? "-") pid=\(a.pid)"
                         + " bundle=\(a.bundleID ?? "nil") front=\(a.isFrontmost) → \(verdict)")
        }
        if assertions.isEmpty { lines.append("  · (none)") }
        return lines.joined(separator: "\n")
    }
}
