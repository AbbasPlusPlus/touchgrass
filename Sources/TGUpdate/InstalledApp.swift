// TGUpdate — where we are installed, what version we are, and where the new build should land.
import Foundation

/// A snapshot of the running bundle. Taken once on the main actor and then passed around as a
/// value, so the installer never has to touch `Bundle.main` from a background context.
public struct InstalledApp: Sendable, Equatable {

    // MARK: Fields

    public let bundleURL: URL
    public let bundleIdentifier: String
    public let shortVersion: String
    public let build: Int

    public init(bundleURL: URL, bundleIdentifier: String, shortVersion: String, build: Int) {
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
        self.shortVersion = shortVersion
        self.build = build
    }

    // MARK: Current process

    /// `nil` when we're not running from a `.app` (e.g. `swift run` during development),
    /// which is exactly when self-updating must be refused.
    public static func current(bundle: Bundle = .main) -> InstalledApp? {
        let url = bundle.bundleURL
        guard url.pathExtension == "app" else { return nil }
        guard let identifier = bundle.bundleIdentifier else { return nil }
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let buildString = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return InstalledApp(
            bundleURL: url.resolvingSymlinksInPath(),
            bundleIdentifier: identifier,
            shortVersion: short,
            build: Int(buildString) ?? 0
        )
    }

    // MARK: Install destination

    /// Normally "replace myself in place". Two cases force a move to /Applications instead:
    /// we're running from a mounted image (`/Volumes/…`, e.g. straight out of a DMG), or the
    /// folder we live in isn't writable — a quarantined Downloads copy, say.
    public var installDestination: URL {
        let parent = bundleURL.deletingLastPathComponent()
        let isOnMountedVolume = parent.path.hasPrefix("/Volumes/")
        let isInTrash = parent.path.contains("/.Trash")
        let writable = FileManager.default.isWritableFile(atPath: parent.path)
        if isOnMountedVolume || isInTrash || !writable {
            return URL(fileURLWithPath: "/Applications", isDirectory: true)
                .appendingPathComponent(bundleURL.lastPathComponent)
        }
        return bundleURL
    }

    /// True when installing means putting the app somewhere it isn't today.
    public var destinationDiffersFromCurrent: Bool {
        installDestination.standardizedFileURL != bundleURL.standardizedFileURL
    }
}
