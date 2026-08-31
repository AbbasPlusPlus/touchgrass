// Screen-recorder policy: a curated app list, counted only while the app shows recording
// evidence (display-sleep assertion or microphone). Pure logic — no system calls.
import Foundation
import Testing
@testable import TGDetection
import TGCore

private func assertion(_ bundleID: String?, name: String? = nil, processName: String? = nil,
                       pid: pid_t = 4321) -> DisplayAssertionInfo {
    DisplayAssertionInfo(pid: pid, processName: processName, assertionType: "PreventUserIdleDisplaySleep",
                         assertionName: nil, appName: name, bundleID: bundleID,
                         isFrontmost: false, ignoredReason: nil)
}

private func micUser(_ bundleID: String, name: String? = nil) -> MicrophoneUser {
    MicrophoneUser(audioObjectID: 1, pid: 1234, rawBundleID: bundleID, bundleID: bundleID, appName: name)
}

@MainActor
private func makeDetector(_ mutate: (inout Settings) -> Void = { _ in }) -> ScreenRecorderDetector {
    var settings = Settings()
    mutate(&settings)
    return ScreenRecorderDetector(settings: settings)
}

// MARK: - Recognition

@Test @MainActor func capAssertionPauses() {
    let detector = makeDetector()
    detector.update(assertions: [assertion("so.cap.desktop", name: "Cap")])
    #expect(detector.reason == .screenRecording(appName: "Cap", bundleID: "so.cap.desktop"))
}

@Test @MainActor func recorderHelperBundleMatches() {
    let detector = makeDetector()
    detector.update(assertions: [assertion("so.cap.desktop.helper")])
    #expect(detector.reason != nil)
}

@Test @MainActor func systemCommandShiftFiveRecorderMatchesByProcessName() {
    let detector = makeDetector()
    detector.update(assertions: [assertion(nil, processName: "screencapture")])
    #expect(detector.reason != nil)
}

@Test @MainActor func recorderMicUsePauses() {
    let detector = makeDetector()
    detector.update(micUsers: [micUser("com.obsproject.obs-studio", name: "OBS")])
    #expect(detector.reason == .screenRecording(appName: "OBS", bundleID: "com.obsproject.obs-studio"))
}

@Test @MainActor func nonRecorderEvidenceIsIgnored() {
    let detector = makeDetector()
    detector.update(assertions: [assertion("com.google.chrome", name: "Chrome")])
    detector.update(micUsers: [micUser("us.zoom.xos")])
    #expect(detector.reason == nil)
}

// MARK: - Clearing

@Test @MainActor func reasonClearsWhenEvidenceGoes() {
    let detector = makeDetector()
    detector.update(assertions: [assertion("so.cap.desktop")])
    #expect(detector.reason != nil)
    detector.update(assertions: [])
    #expect(detector.reason == nil)
}

@Test @MainActor func micEvidenceKeepsReasonAliveWithoutAssertion() {
    let detector = makeDetector()
    detector.update(micUsers: [micUser("so.cap.desktop")])
    detector.update(assertions: [])
    #expect(detector.reason != nil)
}

// MARK: - Settings

@Test @MainActor func toggleOffSilencesTheDetector() {
    let detector = makeDetector { $0.pauseOnScreenRecording = false }
    detector.update(assertions: [assertion("so.cap.desktop")])
    #expect(detector.reason == nil)
}

@Test @MainActor func excludedRecorderDoesNotPause() {
    let detector = makeDetector { $0.screenRecordingExcludedApps = ["so.cap.desktop"] }
    detector.update(assertions: [assertion("so.cap.desktop")])
    #expect(detector.reason == nil)
}

@Test @MainActor func togglingSettingsLiveReevaluates() {
    let detector = makeDetector()
    detector.update(assertions: [assertion("so.cap.desktop")])
    #expect(detector.reason != nil)

    var off = detector.settings
    off.pauseOnScreenRecording = false
    detector.settings = off
    #expect(detector.reason == nil)
}

@Test @MainActor func onChangeFiresOnlyWhenTheReasonMoves() {
    let detector = makeDetector()
    var fired = 0
    detector.onChange = { fired += 1 }

    detector.update(assertions: [assertion("so.cap.desktop")])
    detector.update(assertions: [assertion("so.cap.desktop")])   // same evidence, no change
    #expect(fired == 1)

    detector.update(assertions: [])
    #expect(fired == 2)
}

// MARK: - KnownBundles vocabulary

@Test func knownRecordersAreRecognised() {
    #expect(KnownBundles.isScreenRecorder(bundleID: "so.cap.desktop", processName: nil))
    #expect(KnownBundles.isScreenRecorder(bundleID: "com.obsproject.obs-studio", processName: nil))
    #expect(KnownBundles.isScreenRecorder(bundleID: "net.telestream.screenflow10", processName: nil), "needle match")
    #expect(KnownBundles.isScreenRecorder(bundleID: nil, processName: "screencapture"))
    #expect(!KnownBundles.isScreenRecorder(bundleID: "com.apple.quicktimeplayerx", processName: nil),
            "QuickTime plays video far more often than it records — it stays a .video pause")
    #expect(!KnownBundles.isScreenRecorder(bundleID: nil, processName: nil))
}
