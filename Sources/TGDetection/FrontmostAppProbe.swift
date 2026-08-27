// TGDetection — cheap NSWorkspace queries shared by several detectors. No permissions, no cost.
import AppKit
import Foundation

public struct RunningAppInfo: Sendable, Hashable {
    public let pid: pid_t
    public let bundleID: String?
    public let name: String?

    public var display: String { name ?? bundleID ?? "pid \(pid)" }
}

public enum FrontmostAppProbe {

    @MainActor
    public static func frontmost() -> RunningAppInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return RunningAppInfo(pid: app.processIdentifier, bundleID: app.bundleIdentifier, name: app.localizedName)
    }

    @MainActor
    public static func isFrontmost(pid: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    /// Used when the camera is on but nothing told us *which* app — pick a conferencing app that's open.
    @MainActor
    public static func runningConferencingApp() -> RunningAppInfo? {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && KnownBundles.isConferencing($0.bundleIdentifier)
        }
        // A conferencing app in the foreground is the most likely owner.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let chosen = apps.first { $0.processIdentifier == frontPID } ?? apps.first
        guard let app = chosen else { return nil }
        return RunningAppInfo(pid: app.processIdentifier, bundleID: app.bundleIdentifier, name: app.localizedName)
    }

    @MainActor
    public static func runningApps(matching bundleIDs: [String]) -> [RunningAppInfo] {
        guard !bundleIDs.isEmpty else { return [] }
        return NSWorkspace.shared.runningApplications
            .filter { BundleMatch.matches($0.bundleIdentifier, anyOf: bundleIDs) }
            .map { RunningAppInfo(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier, name: $0.localizedName) }
    }
}
