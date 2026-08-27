// TGMenuBar — bundle ID → app icon, looked up once.
import AppKit

/// `urlForApplication(withBundleIdentifier:)` hits Launch Services and `icon(forFile:)` reads
/// the bundle, so neither belongs in a SwiftUI body that re-runs on every countdown tick. The
/// answer for a given bundle ID doesn't change while the app is open; cache it, misses included,
/// so an app that has since been deleted is only looked for once.
@MainActor
enum AppIconCache {

    private static var cache: [String: NSImage?] = [:]

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        let icon = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[bundleID] = icon
        return icon
    }

    /// For the rare host that wants to forget (an app installed while the panel was open).
    static func invalidate() { cache.removeAll() }
}
