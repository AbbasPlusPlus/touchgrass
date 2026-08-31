// TGDetection — screen recording by a known recorder app (Cap, OBS, Screen Studio…).
//
// There is no public "is the screen being watched?" API (research §Screen sharing — commercial
// apps dlopen SkyLight SPI for that). The public substitute this implements: a curated
// recorder-app list, counted only while the app shows *recording evidence* —
//   • a display-sleep assertion (recorders keep the display awake while capturing), or
//   • the microphone (a voice-over take).
// A recorder that is merely resident holds neither, so nothing pauses until a recording starts.
//
// Pure policy: no polling of its own. ActivityMonitor pushes in the assertion list VideoDetector
// already reads every 3 s and the mic users MicrophoneDetector already attributes.
import Foundation
import TGCore

@MainActor
public final class ScreenRecorderDetector {

    // MARK: Output

    /// `.screenRecording(appName:bundleID:)` while a known recorder shows evidence.
    public private(set) var reason: PauseReason?

    public var settings: Settings {
        didSet { if settings.screenRecordingExcludedApps != oldValue.screenRecordingExcludedApps
                    || settings.pauseOnScreenRecording != oldValue.pauseOnScreenRecording { evaluate() } }
    }
    public var onChange: (@MainActor () -> Void)?

    // MARK: Raw inputs (pushed in by ActivityMonitor)

    private struct Evidence: Hashable {
        let appName: String?
        let bundleID: String?
        let source: String   // "assertion" / "microphone", debug output only
    }

    private var assertionEvidence: [Evidence] = []
    private var micEvidence: [Evidence] = []

    public init(settings: Settings) {
        self.settings = settings
    }

    // MARK: Input

    /// Every display-sleep assertion from the last poll, including ones `.video` ignored —
    /// a recorder is almost never frontmost while it captures, so video's filters don't apply.
    public func update(assertions: [DisplayAssertionInfo]) {
        assertionEvidence = assertions
            .filter { KnownBundles.isScreenRecorder(bundleID: $0.bundleID, processName: $0.processName) }
            .map { Evidence(appName: $0.appName, bundleID: $0.bundleID, source: "assertion") }
        evaluate()
    }

    public func update(micUsers: [MicrophoneUser]) {
        micEvidence = micUsers
            .filter { KnownBundles.isScreenRecorder(bundleID: $0.bundleID ?? $0.rawBundleID, processName: nil) }
            .map { Evidence(appName: $0.appName, bundleID: $0.bundleID ?? $0.rawBundleID, source: "microphone") }
        evaluate()
    }

    public func stop() {
        assertionEvidence = []
        micEvidence = []
        reason = nil
    }

    // MARK: Policy

    private func evaluate() {
        // Assertion evidence first: it names the app doing the capture more reliably than the mic.
        let candidate = (assertionEvidence + micEvidence).first {
            !BundleMatch.matches($0.bundleID, anyOf: settings.screenRecordingExcludedApps)
        }
        let newReason: PauseReason? = (settings.pauseOnScreenRecording && candidate != nil)
            ? .screenRecording(appName: candidate?.appName, bundleID: candidate?.bundleID)
            : nil
        guard newReason != reason else { return }
        reason = newReason
        onChange?()
    }

    // MARK: Debug

    public func debugDescription() -> String {
        var lines = ["recorder: reason=\(reason.map { "\($0)" } ?? "nil")"]
        for e in assertionEvidence + micEvidence {
            let excluded = BundleMatch.matches(e.bundleID, anyOf: settings.screenRecordingExcludedApps)
            lines.append("  · \(e.appName ?? e.bundleID ?? "?") [\(e.source)]"
                         + (excluded ? " → ignored: screenRecordingExcludedApps" : " → COUNTS"))
        }
        if assertionEvidence.isEmpty && micEvidence.isEmpty { lines.append("  · (no recorder evidence)") }
        return lines.joined(separator: "\n")
    }
}
