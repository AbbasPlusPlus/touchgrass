// TGMenuBar — resolving bundle IDs to something a human recognises.
import AppKit

/// Names and icons for the bundle IDs stored in the exclusion lists.
///
/// Lookups hit LaunchServices, so results are cached: an excluded-apps list would otherwise
/// re-resolve every row on every SwiftUI body evaluation.
@MainActor
enum AppInfo {

    private static var urlCache: [String: URL?] = [:]
    private static var iconCache: [String: NSImage] = [:]

    /// Display name. For apps that aren't installed, guess a readable one from the bundle ID
    /// rather than repeating the identifier twice in the same row.
    static func name(for bundleID: String) -> String {
        guard let url = url(for: bundleID) else { return guessName(from: bundleID) }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    /// "com.superwhisper.app" → "Superwhisper"; "com.prakashjoshipax.VoiceInk" → "VoiceInk".
    private static func guessName(from bundleID: String) -> String {
        let ignored: Set<String> = ["app", "desktop", "macos", "mac", "osx", "client"]
        let parts = bundleID.split(separator: ".").map(String.init)
        guard let candidate = parts.reversed().first(where: { !ignored.contains($0.lowercased()) })
        else { return bundleID }
        // Leave existing camel case alone; only capitalise all-lowercase names.
        return candidate == candidate.lowercased() ? candidate.capitalized : candidate
    }

    /// The app's real icon, or a neutral placeholder when it can't be found.
    static func icon(for bundleID: String) -> NSImage {
        if let cached = iconCache[bundleID] { return cached }
        let image: NSImage
        if let url = url(for: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        image.size = NSSize(width: 18, height: 18)
        iconCache[bundleID] = image
        return image
    }

    static func isInstalled(_ bundleID: String) -> Bool { url(for: bundleID) != nil }

    private static func url(for bundleID: String) -> URL? {
        if let cached = urlCache[bundleID] { return cached }
        let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        urlCache[bundleID] = resolved
        return resolved
    }

    // MARK: - Picking

    /// Opens an app chooser rooted at /Applications and returns the chosen bundle identifier.
    static func chooseApplication() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Choose an app"
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // App bundles are directories; without this the panel walks into them.
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.application]

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}
