// TGDetection — turns raw camera + microphone signals into "is the user in a call?".
//
// The rules (from PLAN.md / research §"Recommended detection policy"), in order:
//   • camera on                                  → meeting immediately (cameras are never ambient)
//   • mic used by a known conferencing app or any
//     browser (Meet / Teams-web live in a tab)   → meeting after a 5 s debounce
//   • mic used by a dictation app                → ActivityHint.dictating, never a pause
//   • mic used by an app in meetingExcludedApps  → ignored outright
//   • mic used by anything else                  → ignored (a bare mic is a dictation false positive)
// Clearing is delayed by 3 s of hysteresis so that a Zoom camera blip doesn't resume-and-pause.
import Foundation
import TGCore

@MainActor
public final class MeetingPolicy {

    // MARK: Tunables (research-derived; not user-facing)

    /// Mic-only evidence must persist this long before we call it a meeting.
    public static let micDebounce: TimeInterval = 5
    /// All evidence must be gone this long before we clear.
    public static let clearHysteresis: TimeInterval = 3

    // MARK: Output

    /// `.meeting(appName:bundleID:)` while a call is detected.
    public private(set) var reason: PauseReason?
    /// `.dictating` while a whitelisted dictation app holds the mic.
    public private(set) var hint: ActivityHint?

    public var settings: Settings {
        didSet { evaluate() }
    }
    public var onChange: (@MainActor () -> Void)?

    /// Injected so the debounce/hysteresis can be tested without sleeping.
    private let clock: TGCore.Clock

    // MARK: Raw inputs (pushed in by ActivityMonitor)

    private var cameraInUse = false
    private var cameraNames: [String] = []
    private var micUsers: [MicrophoneUser] = []
    private var micDeviceLevelInUse = false
    private var micAttributionAvailable = false

    // MARK: Debounce / hysteresis state

    private var evidenceSince: Date?
    private var clearPendingSince: Date?
    private var isMeeting = false
    private var meetingApp: (name: String?, bundleID: String?) = (nil, nil)
    private let recheck = OneShotTimer()

    public init(settings: Settings, clock: TGCore.Clock = SystemClock()) {
        self.settings = settings
        self.clock = clock
    }

    // MARK: Input

    public func update(camera: CameraDetector) {
        update(cameraInUse: camera.isCameraInUse, cameraNames: camera.activeDevices.map(\.name))
    }

    public func update(microphone: MicrophoneDetector) {
        update(micUsers: microphone.recordingProcesses,
               deviceLevelInUse: microphone.deviceLevelInUse,
               attributionAvailable: microphone.processAttributionAvailable)
    }

    public func update(cameraInUse: Bool, cameraNames: [String] = []) {
        self.cameraInUse = cameraInUse
        self.cameraNames = cameraNames
        evaluate()
    }

    public func update(micUsers: [MicrophoneUser], deviceLevelInUse: Bool, attributionAvailable: Bool) {
        self.micUsers = micUsers
        micDeviceLevelInUse = deviceLevelInUse
        micAttributionAvailable = attributionAvailable
        evaluate()
    }

    /// Re-runs the policy against unchanged inputs — how a debounce or hysteresis deadline is crossed.
    public func reevaluate() { evaluate() }

    public func stop() {
        recheck.cancel()
        evidenceSince = nil
        clearPendingSince = nil
        isMeeting = false
        reason = nil
        hint = nil
    }

    // MARK: Policy

    private struct Classification {
        var meetingApps: [(name: String?, bundleID: String?)] = []
        var dictationApps: [String] = []
        var ignored: [String] = []
        var excluded: [String] = []
    }

    private func classifyMicUsers() -> Classification {
        var result = Classification()
        for user in micUsers {
            let bundle = user.bundleID ?? user.rawBundleID
            let label = user.display
            if BundleMatch.matches(bundle, anyOf: settings.meetingExcludedApps) {
                result.excluded.append(label)
            } else if BundleMatch.matches(bundle, anyOf: settings.dictationApps) {
                result.dictationApps.append(label)
            } else if KnownBundles.isMeetingCapable(bundle) {
                result.meetingApps.append((user.appName, bundle))
            } else {
                result.ignored.append(label)
            }
        }
        return result
    }

    private func evaluate() {
        let now = clock.now()
        let classification = classifyMicUsers()

        // --- dictation hint (independent of pauseOnMeeting) ---
        let newHint: ActivityHint? = classification.dictationApps.isEmpty ? nil : .dictating

        // --- meeting evidence ---
        let cameraEvidence = cameraInUse && settings.meetingUsesCamera
        let micEvidence = settings.meetingUsesMicrophone && !classification.meetingApps.isEmpty
        let hasEvidence = cameraEvidence || micEvidence

        if hasEvidence {
            clearPendingSince = nil
            if evidenceSince == nil { evidenceSince = now }
            // Camera needs no debounce; mic-only waits `micDebounce`.
            let required = cameraEvidence ? 0 : Self.micDebounce
            let elapsed = now.timeIntervalSince(evidenceSince ?? now)
            if elapsed >= required {
                isMeeting = true
                meetingApp = bestMeetingApp(classification, cameraEvidence: cameraEvidence)
            } else {
                recheck.schedule(after: required - elapsed + 0.05) { [weak self] in self?.evaluate() }
            }
        } else {
            evidenceSince = nil
            if isMeeting {
                if clearPendingSince == nil { clearPendingSince = now }
                let elapsed = now.timeIntervalSince(clearPendingSince ?? now)
                if elapsed >= Self.clearHysteresis {
                    isMeeting = false
                    clearPendingSince = nil
                    meetingApp = (nil, nil)
                } else {
                    recheck.schedule(after: Self.clearHysteresis - elapsed + 0.05) { [weak self] in self?.evaluate() }
                }
            } else {
                clearPendingSince = nil
            }
        }

        let newReason: PauseReason? = (isMeeting && settings.pauseOnMeeting)
            ? .meeting(appName: meetingApp.name, bundleID: meetingApp.bundleID)
            : nil

        guard newReason != reason || newHint != hint else { return }
        reason = newReason
        hint = newHint
        onChange?()
    }

    /// Prefers a mic-attributed conferencing app; a camera alone tells us nothing about *which* app,
    /// so fall back to any running conferencing app, then to nil (the UI copy degrades gracefully).
    private func bestMeetingApp(_ classification: Classification, cameraEvidence: Bool) -> (String?, String?) {
        if let first = classification.meetingApps.first(where: { KnownBundles.isConferencing($0.bundleID) })
            ?? classification.meetingApps.first {
            return (first.name, first.bundleID)
        }
        if cameraEvidence, let running = FrontmostAppProbe.runningConferencingApp() {
            return (running.name, running.bundleID)
        }
        return (nil, nil)
    }

    // MARK: Debug

    private func describe(_ c: Classification, cameraEvidence: Bool, micEvidence: Bool) -> [String] {
        var lines: [String] = []
        lines.append("meeting: active=\(isMeeting) reason=\(reason.map { "\($0)" } ?? "nil") hint=\(hint?.rawValue ?? "nil")")
        lines.append("  evidence camera=\(cameraEvidence)\(cameraNames.isEmpty ? "" : " \(cameraNames)") mic=\(micEvidence)")
        if !c.meetingApps.isEmpty {
            lines.append("  conferencing mic users: " + c.meetingApps.map { $0.bundleID ?? $0.name ?? "?" }.joined(separator: ", "))
        }
        if !c.dictationApps.isEmpty { lines.append("  dictation mic users: " + c.dictationApps.joined(separator: ", ")) }
        if !c.excluded.isEmpty { lines.append("  excluded mic users: " + c.excluded.joined(separator: ", ")) }
        if !c.ignored.isEmpty { lines.append("  ignored (unknown) mic users: " + c.ignored.joined(separator: ", ")) }
        if micDeviceLevelInUse && micUsers.isEmpty {
            lines.append("  note: a device reports running but no process claims input (aggregate/virtual device?)")
        }
        if !micAttributionAvailable {
            lines.append("  note: process attribution unavailable — mic can only ever produce a hint, never a pause")
        }
        if let since = evidenceSince {
            lines.append(String(format: "  debounce: evidence for %.1fs / %.0fs", clock.now().timeIntervalSince(since), Self.micDebounce))
        }
        if let since = clearPendingSince {
            lines.append(String(format: "  hysteresis: clearing in %.1fs", max(0, Self.clearHysteresis - clock.now().timeIntervalSince(since))))
        }
        return lines
    }

    public func debugDescription() -> String {
        let classification = classifyMicUsers()
        return describe(classification,
                        cameraEvidence: cameraInUse && settings.meetingUsesCamera,
                        micEvidence: settings.meetingUsesMicrophone && !classification.meetingApps.isEmpty)
            .joined(separator: "\n")
    }
}
