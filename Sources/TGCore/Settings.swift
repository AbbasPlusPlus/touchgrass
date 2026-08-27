// TGCore — user settings. Codable struct persisted as JSON via SettingsStore.
import Foundation

public struct Settings: Codable, Equatable, Sendable {

    // MARK: Screen breaks
    /// Focused screen time between short breaks.
    public var shortBreakInterval: TimeInterval = 20 * 60
    public var shortBreakDuration: TimeInterval = 30
    public var longBreaksEnabled: Bool = true
    /// Every Nth break is a long break (N=3 → short, short, long).
    public var longBreakEvery: Int = 3
    public var longBreakDuration: TimeInterval = 3 * 60

    // MARK: Pre-break warnings
    public var preBreakWarningSeconds: TimeInterval = 60     // the notification card
    public var preBreakCardVisibleSeconds: TimeInterval = 10  // how long the card stays before auto-hiding
    public var cursorCountdownSeconds: Int = 10               // the cursor-following pill

    // MARK: Enforcement
    public var enforcement: Enforcement = .balanced
    public var balancedSkipDelaySeconds: TimeInterval = 5
    public var snoozesPerDay: Int = 5
    public var snoozesPerSession: Int = 2
    /// Skip becomes "End break" once this fraction of the break has elapsed (long breaks only).
    public var allowEndBreakEarlyAfterFraction: Double = 0.8
    public var doubleEscapeSkips: Bool = true              // false → double-Esc snoozes 5 min
    public var lockScreenOnBreakStart: Bool = false

    // MARK: Smart pause
    public var pauseOnMeeting: Bool = true
    public var meetingUsesCamera: Bool = true
    public var meetingUsesMicrophone: Bool = true
    public var pauseOnVideo: Bool = true
    public var videoFrontmostOnly: Bool = true
    public var pauseOnFullscreen: Bool = true
    public var pauseOnFocusMode: Bool = false
    /// Bundle IDs treated as deep-focus apps.
    public var deepFocusApps: [String] = []
    public var deepFocusMode: DeepFocusMode = .foregroundAndFullscreen
    /// Bundle IDs that should never trigger meeting detection (e.g. audio tools).
    public var meetingExcludedApps: [String] = []
    /// Bundle IDs whose mic use is dictation (delay, don't pause).
    public var dictationApps: [String] = ["com.superwhisper.app", "com.electron.wispr-flow", "com.aquavoice.app", "com.prakashjoshipax.VoiceInk", "com.anthropic.claudefordesktop"]
    /// Bundle IDs that should never count as video playback.
    public var videoExcludedApps: [String] = ["com.spotify.client", "com.apple.FinalCut", "com.blackmagic-design.DaVinciResolve", "com.endel.desktop"]
    /// Microphone/camera device UIDs to ignore.
    public var excludedDeviceUIDs: [String] = []
    /// Delay before breaks resume after a meeting/video ends.
    public var cooldownAfterActivity: TimeInterval = 60
    public var deferWhileTyping: Bool = true
    public var typingBufferSeconds: TimeInterval = 3

    // MARK: Idle / away
    /// After this much no-input, focus time freezes (.idle pause).
    public var idlePauseAfter: TimeInterval = 2 * 60
    /// If away at least this long, the session resets (counts as a break taken).
    public var idleResetAfter: TimeInterval = 5 * 60

    // MARK: Wellness reminders
    public var blinkRemindersEnabled: Bool = false
    public var blinkReminderInterval: TimeInterval = 10 * 60
    public var postureRemindersEnabled: Bool = false
    public var postureReminderInterval: TimeInterval = 20 * 60
    public var wellnessDimsScreen: Bool = false
    public var wellnessMainScreenOnly: Bool = true

    // MARK: Appearance
    public var background: BreakBackground = .wallpaper
    public var showTitle: Bool = true
    public var showSubtitle: Bool = true
    public var showClock: Bool = true
    public var shortBreakMessages: [String] = [
        "Relax those eyes|Find a distant spot to rest your eyes on while you wait",
        "Breathe|In through the nose, out through the mouth",
        "A moment of pause|Let your eyes wander for a moment",
    ]
    public var longBreakMessages: [String] = [
        "Step away|Stretch, get some water, look out a window",
        "Go touch grass|Your screen will still be here when you get back",
    ]
    public var showCountdownOnAllDisplays: Bool = false

    // MARK: Sounds
    public var soundOnBreakStart: Bool = true
    public var soundOnBreakEnd: Bool = true
    public var soundOnPreBreak: Bool = false
    public var soundStyle: SoundStyle = .bell
    public var volume: Double = 0.6   // 0...1

    // MARK: General
    public var launchAtLogin: Bool = false
    public var menuBarStyle: MenuBarStyle = .iconAndTime
    public var hasCompletedOnboarding: Bool = false

    // MARK: Keyboard shortcuts
    /// Global hotkeys keyed by `HotkeyAction.rawValue` (TGMenuBar owns the action vocabulary).
    /// Empty by default — nothing is registered until the user records a shortcut.
    public var hotkeys: [String: Hotkey] = [:]

    public init() {}

    /// "Title|Subtitle" → (title, subtitle?)
    public static func splitMessage(_ s: String) -> (title: String, subtitle: String?) {
        let parts = s.split(separator: "|", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
        return (parts.first ?? "", parts.count > 1 ? parts[1] : nil)
    }
}

public enum DeepFocusMode: String, Codable, Sendable, Hashable, CaseIterable {
    case foregroundAndFullscreen, foreground, open
    public var title: String {
        switch self {
        case .foregroundAndFullscreen: return "When in foreground & fullscreen"
        case .foreground: return "When in foreground"
        case .open: return "When open"
        }
    }
}

public enum MenuBarStyle: String, Codable, Sendable, Hashable, CaseIterable {
    case iconOnly, timeOnly, iconAndTime
}

/// A recorded global keyboard shortcut. `keyCode` is a virtual key code (Carbon `kVK_*`),
/// `modifiers` is a Carbon modifier mask (`cmdKey | optionKey | controlKey | shiftKey`).
public struct Hotkey: Codable, Equatable, Sendable, Hashable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

// MARK: - Persistence

/// JSON file in ~/Library/Application Support/TouchGrass/settings.json. Observable so UI can bind.
@MainActor
public final class SettingsStore: ObservableObject {
    @Published public var settings: Settings {
        didSet { save() }
    }
    private let url: URL

    public init(url: URL? = nil) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TouchGrass", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = url ?? dir.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: self.url),
           let s = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = s
        } else {
            settings = Settings()
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(settings) { try? data.write(to: url, options: .atomic) }
    }
}
