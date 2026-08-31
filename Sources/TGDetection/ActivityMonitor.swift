// TGDetection — the single object the app talks to. Composes every detector and merges their output
// into `pauseReasons` / `activityHint` / `idleSeconds`.
//
// Push where the OS allows it (CoreMediaIO + CoreAudio property listeners, NSWorkspace and
// DistributedNotificationCenter notifications); poll only where there is no notification API
// (power assertions 3 s, window list 5 s, idle 5 s→1 s). Everything lands on the MainActor.
import AppKit
import Combine
import Foundation
import TGCore

@MainActor
public final class ActivityMonitor: ObservableObject {

    // MARK: Published output (the contract with BreakEngine)

    @Published public private(set) var pauseReasons: Set<PauseReason> = []
    @Published public private(set) var activityHint: ActivityHint? = nil
    @Published public private(set) var idleSeconds: TimeInterval = 0

    /// Lock / screensaver / sleep / session state.
    @Published public private(set) var systemState = SystemState()

    /// The app in front, or `nil` when it is TouchGrass itself (or nothing nameable). Pushed
    /// by `NSWorkspace`, never polled — the app feeds it to `StatsRecorder` so the Stats tab
    /// can say where the day went.
    @Published public private(set) var frontmostApp: FrontmostApp?

    /// Split idle times — the engine uses these to tell "away" from "reading".
    public var keyboardIdleSeconds: TimeInterval { idle.keyboardIdleSeconds }
    public var mouseIdleSeconds: TimeInterval { mouseIdleSecondsStorage }

    /// Fired after every recomputation whose result differed. Convenience for non-Combine callers.
    public var onChange: (@MainActor (Set<PauseReason>, ActivityHint?) -> Void)?

    // MARK: Settings

    /// Live-editable. Assigning re-pushes the relevant slices into every detector and re-evaluates.
    public var settings: Settings {
        didSet { applySettings() }
    }

    // MARK: Detectors

    public let camera = CameraDetector()
    public let microphone = MicrophoneDetector()
    public let meeting: MeetingPolicy
    public let video: VideoDetector
    public let screenRecorder: ScreenRecorderDetector
    public let fullscreen: FullscreenDetector
    public let deepFocus: DeepFocusDetector
    public let idle = IdleDetector()
    public let input = InputActivityDetector()
    public let system = SystemStateObserver()
    public let frontmost = FrontmostTracker()

    private var isRunning = false
    private var mouseIdleSecondsStorage: TimeInterval = 0
    /// Listener storms (a camera turning on fires several) collapse into one recomputation.
    private let recomputeCoalescer = OneShotTimer()

    // MARK: Init

    public init(settings: Settings) {
        self.settings = settings
        self.meeting = MeetingPolicy(settings: settings)
        self.video = VideoDetector(settings: settings)
        self.screenRecorder = ScreenRecorderDetector(settings: settings)
        let fullscreen = FullscreenDetector(settings: settings)
        self.fullscreen = fullscreen
        self.deepFocus = DeepFocusDetector(settings: settings) { [weak fullscreen] bundleID in
            fullscreen?.isFullscreen(bundleID: bundleID) ?? false
        }
        wire()
    }

    private func wire() {
        camera.onChange = { [weak self] in
            guard let self else { return }
            self.meeting.update(camera: self.camera)
            self.scheduleRecompute()
        }
        microphone.onChange = { [weak self] in
            guard let self else { return }
            self.meeting.update(microphone: self.microphone)
            self.screenRecorder.update(micUsers: self.microphone.recordingProcesses)
            self.scheduleRecompute()
        }
        meeting.onChange = { [weak self] in self?.scheduleRecompute() }
        video.onChange = { [weak self] in
            guard let self else { return }
            // The recorder policy rides video's 3 s assertion poll rather than polling again.
            self.screenRecorder.update(assertions: self.video.assertions)
            self.scheduleRecompute()
        }
        screenRecorder.onChange = { [weak self] in self?.scheduleRecompute() }
        fullscreen.onChange = { [weak self] in
            // Deep focus in `foregroundAndFullscreen` mode depends on the fullscreen verdict.
            self?.deepFocus.refresh()
            self?.scheduleRecompute()
        }
        deepFocus.onChange = { [weak self] in self?.scheduleRecompute() }
        idle.onChange = { [weak self] in self?.scheduleRecompute() }
        input.onChange = { [weak self] in self?.scheduleRecompute() }
        system.onChange = { [weak self] in self?.scheduleRecompute() }
        system.onWake = { [weak self] in
            // Idle counters and every cached pid are meaningless across sleep/unlock.
            ProcessAppResolver.shared.invalidate()
            self?.idle.resetAndRefresh()
            self?.refreshAll()
        }
        // Nothing to recompute: the frontmost app is an output of its own, not an input to
        // the pause/hint merge.
        frontmost.onChange = { [weak self] app in self?.frontmostApp = app }
    }

    // MARK: Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        applySettings()
        system.start()
        camera.start()
        microphone.start()
        video.start()
        fullscreen.start()
        deepFocus.start()
        idle.start()
        frontmost.start()
        meeting.update(camera: camera)
        meeting.update(microphone: microphone)
        screenRecorder.update(assertions: video.assertions)
        screenRecorder.update(micUsers: microphone.recordingProcesses)
        recompute()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        recomputeCoalescer.cancel()
        camera.stop()
        microphone.stop()
        meeting.stop()
        video.stop()
        screenRecorder.stop()
        fullscreen.stop()
        deepFocus.stop()
        idle.stop()
        frontmost.stop()
        input.disarm()
        system.stop()
        pauseReasons = []
        activityHint = nil
        idleSeconds = 0
    }

    /// Forces every detector to re-read (used on wake and when the caller wants a fresh snapshot).
    public func refreshAll() {
        camera.refresh()
        microphone.refresh()
        video.refresh()
        fullscreen.refresh()
        deepFocus.refresh()
        idle.refresh()
        frontmost.refresh()
        recompute()
    }

    // MARK: Activity hints (typing / dragging)

    /// Arm ~15 s before a break so typing/dragging can defer it. Costs one 1 Hz timer while armed.
    public func armActivityHints() { input.arm() }
    public func disarmActivityHints() { input.disarm() }
    public var isActivityHintDetectionArmed: Bool { input.isArmed }

    // MARK: Settings fan-out

    private func applySettings() {
        camera.excludedUIDs = settings.excludedDeviceUIDs
        microphone.excludedUIDs = settings.excludedDeviceUIDs
        meeting.settings = settings
        video.settings = settings
        screenRecorder.settings = settings
        fullscreen.settings = settings
        deepFocus.settings = settings
        idle.idlePauseAfter = settings.idlePauseAfter
        scheduleRecompute()
    }

    // MARK: Merge

    private func scheduleRecompute() {
        recomputeCoalescer.schedule(after: 0.05) { [weak self] in self?.recompute() }
    }

    private func recompute() {
        var reasons: Set<PauseReason> = []

        if settings.pauseOnMeeting, let meetingReason = meeting.reason { reasons.insert(meetingReason) }
        if settings.pauseOnVideo, let videoReason = video.reason { reasons.insert(videoReason) }
        if settings.pauseOnScreenRecording, let recordingReason = screenRecorder.reason { reasons.insert(recordingReason) }
        if settings.pauseOnFullscreen, let fullscreenReason = fullscreen.reason { reasons.insert(fullscreenReason) }
        if !settings.deepFocusApps.isEmpty, let deepFocusReason = deepFocus.reason { reasons.insert(deepFocusReason) }
        if idle.idleSeconds >= settings.idlePauseAfter { reasons.insert(.idle) }
        if systemStateSaysLocked { reasons.insert(.screenLocked) }

        // Dictation is a hint, never a pause; typing/dragging only exist while armed.
        let hint = Self.mergedHint(meeting: meeting.hint,
                                   input: input.hint,
                                   deferWhileTyping: settings.deferWhileTyping)

        let newIdle = idle.idleSeconds
        let newSystemState = system.state
        mouseIdleSecondsStorage = idle.mouseIdleSeconds

        // `@Published` fires on every assignment, so only assign what actually moved — otherwise a
        // 1 Hz idle poll would invalidate every bound SwiftUI view once a second.
        let outputChanged = reasons != pauseReasons || hint != activityHint
        if reasons != pauseReasons { pauseReasons = reasons }
        if hint != activityHint { activityHint = hint }
        if abs(newIdle - idleSeconds) >= 0.5 { idleSeconds = newIdle }
        if newSystemState != systemState { systemState = newSystemState }

        // Only the merged pause/hint output is worth waking the app for; idle has its own publisher.
        if outputChanged { onChange?(reasons, hint) }
    }

    /// The single rule that decides what the engine sees, pulled out so it can be tested directly.
    ///
    /// Dictation rides the microphone (`MeetingPolicy`), so it is reported whatever the state of
    /// the keyboard/drag detector — which only runs while armed, in the last seconds before a
    /// break — and whatever `deferWhileTyping` says, because that switch is about typing.
    static func mergedHint(meeting: ActivityHint?,
                           input: ActivityHint?,
                           deferWhileTyping: Bool) -> ActivityHint? {
        meeting ?? (deferWhileTyping ? input : nil)
    }

    private var systemStateSaysLocked: Bool {
        system.state.isLocked || system.state.isScreensaverActive
            || system.state.isDisplayAsleep || !system.state.isSessionActive
    }

    // MARK: Debug

    /// Every raw signal behind the merged output — the thing to paste into a bug report.
    public func debugSnapshot() -> String {
        let stamp = ISO8601DateFormatter().string(from: Date())
        var lines: [String] = []
        lines.append("── ActivityMonitor \(stamp) \(isRunning ? "" : "(stopped) ")──")
        lines.append("pauseReasons: " + (pauseReasons.isEmpty ? "none"
                                         : pauseReasons.map(\.shortLabel).sorted().joined(separator: ", ")))
        for r in pauseReasons.sorted(by: { $0.shortLabel < $1.shortLabel }) { lines.append("   • \(r)") }
        lines.append("activityHint: \(activityHint?.rawValue ?? "nil")")
        lines.append(system.debugDescription())
        lines.append(camera.debugDescription())
        lines.append(microphone.debugDescription())
        lines.append(meeting.debugDescription())
        lines.append(video.debugDescription())
        lines.append(screenRecorder.debugDescription())
        lines.append(fullscreen.debugDescription())
        lines.append(deepFocus.debugDescription())
        lines.append(idle.debugDescription())
        lines.append(input.debugDescription())
        lines.append(frontmost.debugDescription())
        lines.append("settings: meeting=\(settings.pauseOnMeeting)(cam=\(settings.meetingUsesCamera),mic=\(settings.meetingUsesMicrophone))"
                     + " video=\(settings.pauseOnVideo) recording=\(settings.pauseOnScreenRecording)"
                     + " fullscreen=\(settings.pauseOnFullscreen)"
                     + " deferWhileTyping=\(settings.deferWhileTyping)"
                     + " idlePauseAfter=\(Int(settings.idlePauseAfter))s")
        return lines.joined(separator: "\n")
    }
}
