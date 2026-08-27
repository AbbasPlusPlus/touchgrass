// TGDetection — which app is in front, pushed rather than polled.
//
// `NSWorkspace.didActivateApplicationNotification` fires the moment the frontmost application
// changes, so this costs one notification observer and nothing at all while the user stays in
// one app. No Accessibility, no Screen Recording, no window titles: the frontmost application
// is public information, and its bundle ID plus its localized name is all this reports.
import AppKit
import Foundation

// MARK: - Value

/// The app in front, reduced to the two things the stats need.
public struct FrontmostApp: Sendable, Hashable {
    public let bundleID: String
    /// Localized name ("Safari"). Falls back to the bundle ID when the app won't give one.
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name.isEmpty ? bundleID : name
    }
}

// MARK: - Tracker

/// Watches the frontmost application and reports changes through `onChange`.
///
/// Helper processes (`Slack Helper`, a browser's GPU process) are mapped back to the app that
/// owns them with `ProcessAppResolver`, so a day's usage is filed under "Slack" rather than
/// under three helpers nobody launched.
@MainActor
public final class FrontmostTracker {

    // MARK: State

    public private(set) var current: FrontmostApp?
    public var onChange: (@MainActor (FrontmostApp?) -> Void)?

    /// TouchGrass's own bundle ID. The settings window and the onboarding flow activate the
    /// app, and "you spent nine minutes in TouchGrass" is a fact about this feature rather than
    /// about the user's day — those seconds stay in total screen time and are attributed to
    /// nobody.
    private let excludedBundleID: String?
    private var observer: NSObjectProtocol?
    private var isRunning = false

    // MARK: Init

    public init(excludedBundleID: String? = Bundle.main.bundleIdentifier) {
        self.excludedBundleID = excludedBundleID
    }

    deinit { if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }

    // MARK: Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.activated(app) }
        }
        refresh()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        publish(nil)
    }

    /// Re-reads the frontmost app. Used on wake, where the activation that happened while the
    /// machine was asleep was never delivered.
    public func refresh() {
        activated(NSWorkspace.shared.frontmostApplication)
    }

    // MARK: Resolution

    private func activated(_ app: NSRunningApplication?) {
        guard isRunning else { return }
        publish(app.flatMap(identify))
    }

    private func identify(_ app: NSRunningApplication) -> FrontmostApp? {
        if let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
            guard bundleID != excludedBundleID else { return nil }
            return FrontmostApp(bundleID: bundleID, name: app.localizedName ?? bundleID)
        }
        // No bundle of its own: a helper, or something launched from a terminal. Walk to the
        // owner — the same resolution the detectors use for camera/mic clients.
        let identity = ProcessAppResolver.shared.identity(for: app.processIdentifier)
        guard let bundleID = identity.bundleID, bundleID != excludedBundleID else { return nil }
        return FrontmostApp(bundleID: bundleID, name: identity.name ?? bundleID)
    }

    private func publish(_ app: FrontmostApp?) {
        guard app != current else { return }
        current = app
        onChange?(app)
    }

    // MARK: Debug

    public func debugDescription() -> String {
        "frontmost: \(current.map { "\($0.name) (\($0.bundleID))" } ?? "none")"
    }
}
