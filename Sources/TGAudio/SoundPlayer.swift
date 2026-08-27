// TGAudio — bundled break sounds.
//
// One `AVAudioPlayer` per asset, held strongly in a cache and prepared ahead of
// time: allocating a player at the moment a break starts is what makes the first
// chime of a session arrive late and clipped.

import AVFoundation
import Foundation
import TGCore

// MARK: - Events

/// The four moments TouchGrass makes a sound. The raw value is the second half
/// of every asset's file name: `<style>-<event>.m4a`.
public enum SoundEvent: String, Codable, Sendable, Hashable, CaseIterable {
    case breakStart
    case breakEnd
    case preBreak
    case wellness
}

// MARK: - Player

@MainActor
public final class SoundPlayer {

    // MARK: Configuration

    /// Overrides the bundled asset for every event when set. `SoundStyle.none`
    /// still silences everything — "None" means none.
    public var customSoundURL: URL?

    /// Volume `preview(_:event:)` uses, for callers that have no Settings value
    /// at hand (the settings window plays previews at a fixed, audible level).
    public var previewVolume: Double = 0.7

    // MARK: State

    /// Strong refs. An `AVAudioPlayer` that goes out of scope stops mid-sound.
    private var players: [URL: AVAudioPlayer] = [:]
    /// URLs that failed to load once; don't keep retrying on every break.
    private var unloadable: Set<URL> = []
    /// In-flight `stopAll` fades, so a sound restarted during its own fade-out
    /// isn't killed a moment later by the stop that was already scheduled.
    private var pendingStops: [URL: UUID] = [:]
    /// Newest deferred `preview`, so only the last click of a burst is heard.
    private var previewToken: UUID?

    /// How long `stopAll` takes to duck a sound before cutting it. Cutting a
    /// ringing bowl at full amplitude is a click.
    private static let stopFade: TimeInterval = 0.06

    public init() {}

    // MARK: Playback

    /// Plays `event` in `style`. Silent and non-throwing when the style is
    /// `.none` or the asset is missing — a break must never fail over audio.
    public func play(_ style: SoundStyle, event: SoundEvent, volume: Double) {
        guard let url = url(for: style, event: event), let player = player(for: url) else { return }
        pendingStops[url] = nil
        if player.isPlaying { player.stop() }         // also cancels any running fade
        player.currentTime = 0
        player.volume = Self.perceptualGain(volume)
        player.play()
    }

    /// Plays a style at `previewVolume`, ducking whatever was already sounding
    /// first so rapid clicking in Settings neither stacks sounds nor clicks.
    /// The new cue waits out the duck — 80 ms, below the threshold of feeling
    /// unresponsive.
    public func preview(_ style: SoundStyle, event: SoundEvent = .breakStart) {
        let wasSounding = players.values.contains { $0.isPlaying }
        stopAll()
        guard wasSounding else {
            play(style, event: event, volume: previewVolume)
            return
        }
        let token = UUID()
        previewToken = token
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(Self.stopFade * 1000) + 25))
            guard let self, self.previewToken == token else { return }
            self.previewToken = nil
            self.play(style, event: event, volume: self.previewVolume)
        }
    }

    /// Fades everything out over `stopFade` and then stops it.
    public func stopAll() {
        for (url, player) in players where player.isPlaying {
            let token = UUID()
            pendingStops[url] = token
            player.setVolume(0, fadeDuration: Self.stopFade)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(Self.stopFade * 1000) + 20))
                guard let self, self.pendingStops[url] == token else { return }
                self.pendingStops[url] = nil
                player.stop()
                player.currentTime = 0
            }
        }
    }

    /// Stops everything immediately, without the fade. For teardown.
    public func stopAllImmediately() {
        previewToken = nil
        pendingStops.removeAll()
        for player in players.values where player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
    }

    // MARK: Preloading

    /// Decodes and prepares every event of a style. Call when the style changes.
    public func preload(_ style: SoundStyle) {
        for event in SoundEvent.allCases {
            guard let url = url(for: style, event: event) else { continue }
            _ = player(for: url)
        }
    }

    public func preloadAll() {
        for style in SoundStyle.allCases { preload(style) }
    }

    // MARK: Introspection

    /// Resolved file for a style/event, honouring `customSoundURL`. `nil` when
    /// the style is `.none` or the asset isn't in the bundle.
    public func url(for style: SoundStyle, event: SoundEvent) -> URL? {
        guard style != SoundStyle.none else { return nil }
        if let customSoundURL { return customSoundURL }
        return Self.assetURL(named: "\(style.rawValue)-\(event.rawValue)")
    }

    public func duration(for style: SoundStyle, event: SoundEvent) -> TimeInterval? {
        guard let url = url(for: style, event: event) else { return nil }
        return player(for: url)?.duration
    }

    public func isAvailable(_ style: SoundStyle, event: SoundEvent) -> Bool {
        url(for: style, event: event).map { player(for: $0) != nil } ?? false
    }

    /// Where the sounds were found. For diagnostics (`tg-sound-demo`).
    public static var resourceBundleURL: URL? { resourceBundle?.bundleURL }

    // MARK: Cache

    private func player(for url: URL) -> AVAudioPlayer? {
        if let cached = players[url] { return cached }
        guard !unloadable.contains(url) else { return nil }
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            unloadable.insert(url)
            return nil
        }
        player.numberOfLoops = 0
        player.prepareToPlay()
        players[url] = player
        return player
    }

    // MARK: Volume

    /// A 0…1 slider maps to loudness far better squared than raw: `pow(v, 2)`
    /// is the cheap stand-in for a dB taper, so 50 % sounds like half.
    public static func perceptualGain(_ volume: Double) -> Float {
        Float(pow(min(max(volume, 0), 1), 2))
    }

    // MARK: Bundle resolution

    private static let bundleName = "TouchGrass_TGAudio"

    /// SwiftPM's generated `Bundle.module` calls `fatalError` when it can't find
    /// the resource bundle. We run the same search it does — plus the
    /// executable's own directory, which it doesn't check and which is where the
    /// bundle sits for a plain `swift build` binary — and fall back to silence
    /// instead of killing the app.
    ///
    /// Layouts covered: `TouchGrass.app/Contents/Resources/` (via
    /// `Bundle.main.resourceURL`) and `.build/<config>/` (next to the binary).
    private static let resourceBundle: Bundle? = {
        var seen = Set<String>()
        var directories: [URL] = []
        func consider(_ url: URL?) {
            guard let url, seen.insert(url.standardizedFileURL.path).inserted else { return }
            directories.append(url)
        }
        consider(Bundle.main.resourceURL)
        consider(Bundle(for: BundleToken.self).resourceURL)
        consider(Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent())
        consider(Bundle.main.bundleURL)
        consider(Bundle.main.executableURL?.deletingLastPathComponent())
        consider(URL(fileURLWithPath: CommandLine.arguments.first ?? ".")
            .deletingLastPathComponent())

        for directory in directories {
            let candidate = directory.appendingPathComponent("\(bundleName).bundle")
            if FileManager.default.fileExists(atPath: candidate.path),
               let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        // Resources flattened straight into the app bundle.
        return Bundle.main
    }()

    /// Assets ship as `.m4a`; the others are here so a hand-dropped replacement
    /// keeps working.
    private static let extensions = ["m4a", "wav", "caf", "aiff", "aif", "mp3"]

    private static func assetURL(named name: String) -> URL? {
        guard let bundle = resourceBundle else { return nil }
        for ext in extensions {
            if let url = bundle.url(forResource: name, withExtension: ext) { return url }
        }
        return nil
    }
}

/// Anchor for `Bundle(for:)` — locates the code that contains this module.
private final class BundleToken {}
