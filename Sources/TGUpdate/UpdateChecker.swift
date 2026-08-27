// TGUpdate — the observable front door: when to look, what we found, and the install trigger.
import AppKit
import Combine
import Foundation

/// Polls a JSON appcast, downloads and verifies a newer build in the background, and swaps it
/// in when the user says so.
///
/// TouchGrass is ad-hoc signed and distributed from a landing page, so there is no Developer ID
/// to pin and no Sparkle EdDSA signature. The chain of trust is: HTTPS to a repository only the
/// author can push to, plus a SHA-256 in the appcast that the zip must match byte for byte.
@MainActor
public final class UpdateChecker: ObservableObject {

    /// The app-wide instance. The app configures it at launch; Settings reads it directly so
    /// the updater doesn't have to be threaded through every view.
    public static let shared = UpdateChecker()

    // MARK: - Published state

    @Published public private(set) var state: UpdateState = .idle
    @Published public private(set) var lastCheck: Date?

    /// Mirrors `Settings.autoUpdateEnabled`. The app keeps this in sync; manual `checkNow()`
    /// works regardless.
    @Published public var automaticChecksEnabled: Bool = true

    /// Fired once per staged update, with the display version ("0.2.0 (3)"). The app hands this
    /// to the status bar, which grows a "Restart to update" item.
    public var onUpdateAvailable: ((String) -> Void)?

    // MARK: - Configuration

    public static let defaultFeedURL = URL(
        string: "https://raw.githubusercontent.com/AbbasPlusPlus/touchgrass-releases/main/appcast.json"
    )

    public var feedURL: URL

    /// Wait this long after launch before the first check — a menu-bar app's first ten seconds
    /// belong to the user, not to us.
    private let launchDelay: TimeInterval = 10
    private let checkInterval: TimeInterval = 24 * 60 * 60
    /// A relaunch loop must not turn into a request loop.
    private let launchCheckFloor: TimeInterval = 60 * 60
    /// Wall-clock is the authority; this only decides how often we consult it.
    private let pollInterval: TimeInterval = 30 * 60

    private static let lastCheckDefaultsKey = "com.abbasplusplus.touchgrass.update.lastCheck"

    // MARK: - Internals

    private var pollTimer: Timer?
    private var launchTimer: Timer?
    private var staged: StagedUpdate?
    private var inFlight = false
    private var didStart = false

    // MARK: - Init

    public init(feedURL: URL? = nil) {
        self.feedURL = feedURL
            ?? Self.defaultFeedURL
            ?? URL(fileURLWithPath: "/dev/null")
        let stored = UserDefaults.standard.double(forKey: Self.lastCheckDefaultsKey)
        lastCheck = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    deinit {
        // Timers are main-run-loop bound; invalidating them is the owner's job on teardown,
        // and a checker only dies when the process does.
    }

    // MARK: - Schedule

    /// Idempotent. Arms the launch check and a coarse poll — no sub-second timers, and the poll
    /// only compares two `Date`s, so an idle day costs 48 wakeups.
    public func start() {
        guard !didStart else { return }
        didStart = true

        let launch = Timer(timeInterval: launchDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue(minimumAge: self?.launchCheckFloor ?? 0) }
        }
        launch.tolerance = 5
        RunLoop.main.add(launch, forMode: .common)
        launchTimer = launch

        let poll = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue(minimumAge: self?.checkInterval ?? 0) }
        }
        poll.tolerance = pollInterval / 6
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll
    }

    public func stop() {
        launchTimer?.invalidate(); launchTimer = nil
        pollTimer?.invalidate(); pollTimer = nil
        didStart = false
    }

    private func checkIfDue(minimumAge: TimeInterval) {
        guard automaticChecksEnabled else { return }
        guard Date().timeIntervalSince(lastCheck ?? .distantPast) >= minimumAge else { return }
        check()
    }

    // MARK: - Check

    /// The Settings button. Always goes to the network, even with automatic checks off.
    public func checkNow() {
        check()
    }

    private func check() {
        // A staged build is the end of the road until the user restarts.
        if case .readyToInstall = state { return }
        guard !inFlight else { return }
        inFlight = true
        state = .checking

        let app = InstalledApp.current()
        let url = feedURL

        Task { [weak self] in
            do {
                let release = try await UpdateDownloader.fetchAppcast(from: url)
                await self?.handle(release: release, app: app)
            } catch {
                self?.finish(with: .error(Self.describe(error)))
            }
        }
    }

    private func handle(release: Release, app: InstalledApp?) async {
        recordCheck()

        let currentVersion = app?.shortVersion ?? Self.bundleShortVersion
        let currentBuild = app?.build ?? Self.bundleBuild
        guard release.isNewer(thanVersion: currentVersion, build: currentBuild) else {
            finish(with: .upToDate)
            return
        }

        guard let app else {
            // Running from `swift run` / a loose binary: report it, but don't pretend we can swap.
            finish(with: .error(Self.describe(UpdateError.notAnAppBundle)))
            return
        }

        state = .available(release)
        state = .downloading(0)

        do {
            let staged = try await UpdateInstaller.stage(release: release, app: app) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(fraction)
                }
            }
            self.staged = staged
            finish(with: .readyToInstall(release))
            onUpdateAvailable?(release.displayVersion)
        } catch {
            finish(with: .error(Self.describe(error)))
        }
    }

    private func finish(with newState: UpdateState) {
        inFlight = false
        state = newState
    }

    private func recordCheck() {
        let now = Date()
        lastCheck = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastCheckDefaultsKey)
    }

    // MARK: - Install

    /// Swaps the staged build in and relaunches. Nothing happens unless a verified build is
    /// already sitting in staging, so this can be wired to a menu item without a guard.
    public func installAndRelaunch() {
        guard let staged else { return }
        guard !inFlight else { return }
        inFlight = true

        Task { [weak self] in
            do {
                try await Self.performInstall(staged)
                UpdateInstaller.scheduleRelaunch(at: staged.destination)
                NSApplication.shared.terminate(nil)
            } catch {
                guard let self else { return }
                self.staged = nil
                self.finish(with: .error(Self.describe(error)))
            }
        }
    }

    /// `nonisolated` on purpose: the copy blocks, and it must not block the main actor while
    /// the menu bar is still on screen.
    private nonisolated static func performInstall(_ staged: StagedUpdate) async throws {
        try UpdateInstaller.install(staged)
    }

    /// Reveals the staged build so a user who hit a permissions wall can drag it themselves.
    public func revealStagedUpdateInFinder() {
        guard let staged else { return }
        NSWorkspace.shared.activateFileViewerSelecting([staged.appURL])
    }

    // MARK: - Description helpers

    public var currentVersionDescription: String {
        let build = Self.bundleBuild
        return build > 0 ? "\(Self.bundleShortVersion) (\(build))" : Self.bundleShortVersion
    }

    private static var bundleShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static var bundleBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
