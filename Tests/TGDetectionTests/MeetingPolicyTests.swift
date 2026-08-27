// Meeting policy is the only piece of TGDetection with no system calls in its decision path, and the
// only one whose rules are subtle. A fake clock drives the 5 s debounce and 3 s hysteresis directly.
import Foundation
import Testing
@testable import TGDetection
import TGCore

private final class FakeClock: TGCore.Clock, @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_700_000_000)
    func now() -> Date { date }
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

private func micUser(_ bundleID: String, name: String? = nil, pid: pid_t = 1234) -> MicrophoneUser {
    MicrophoneUser(audioObjectID: 1, pid: pid, rawBundleID: bundleID, bundleID: bundleID, appName: name)
}

@MainActor
private func makePolicy(_ mutate: (inout Settings) -> Void = { _ in }) -> (MeetingPolicy, FakeClock) {
    var settings = Settings()
    mutate(&settings)
    let clock = FakeClock()
    return (MeetingPolicy(settings: settings, clock: clock), clock)
}

@MainActor
private func setMic(_ policy: MeetingPolicy, _ users: [MicrophoneUser]) {
    policy.update(micUsers: users, deviceLevelInUse: !users.isEmpty, attributionAvailable: true)
}

// MARK: - Camera

@Test @MainActor func cameraPausesImmediately() {
    let (policy, _) = makePolicy()
    policy.update(cameraInUse: true, cameraNames: ["FaceTime HD Camera"])
    #expect(policy.reason != nil)
}

@Test @MainActor func cameraIgnoredWhenMeetingUsesCameraIsOff() {
    let (policy, _) = makePolicy { $0.meetingUsesCamera = false }
    policy.update(cameraInUse: true)
    #expect(policy.reason == nil)
}

@Test @MainActor func cameraClearsAfterHysteresisNotBefore() {
    let (policy, clock) = makePolicy()
    policy.update(cameraInUse: true)
    #expect(policy.reason != nil)

    policy.update(cameraInUse: false)
    #expect(policy.reason != nil, "must not resume the instant the camera blinks off")

    clock.advance(MeetingPolicy.clearHysteresis - 0.5)
    policy.reevaluate()
    #expect(policy.reason != nil)

    clock.advance(1)
    policy.reevaluate()
    #expect(policy.reason == nil)
}

// MARK: - Microphone attribution

@Test @MainActor func knownConferencingMicPausesOnlyAfterDebounce() {
    let (policy, clock) = makePolicy()
    setMic(policy, [micUser("us.zoom.xos", name: "zoom.us")])
    #expect(policy.reason == nil, "mic alone must wait out the debounce")

    clock.advance(MeetingPolicy.micDebounce - 0.5)
    policy.reevaluate()
    #expect(policy.reason == nil)

    clock.advance(1)
    policy.reevaluate()
    if case .meeting(let appName, let bundleID) = policy.reason {
        #expect(appName == "zoom.us")
        #expect(bundleID == "us.zoom.xos")
    } else {
        Issue.record("expected a meeting reason, got \(String(describing: policy.reason))")
    }
}

@Test @MainActor func browserMicCountsAsMeetingForGoogleMeet() {
    let (policy, clock) = makePolicy()
    setMic(policy, [micUser("com.google.Chrome", name: "Google Chrome")])
    clock.advance(MeetingPolicy.micDebounce + 1)
    policy.reevaluate()
    #expect(policy.reason != nil)
}

@Test @MainActor func helperBundleIDsStillMatchTheirParentEntry() {
    // CoreAudio reports helpers like this; the exclusion/known lists must still match.
    let (policy, clock) = makePolicy()
    setMic(policy, [micUser("com.tinyspeck.slackmacgap.helper", name: "Slack")])
    clock.advance(MeetingPolicy.micDebounce + 1)
    policy.reevaluate()
    #expect(policy.reason != nil)
}

@Test @MainActor func unknownAppMicNeverPauses() {
    let (policy, clock) = makePolicy()
    setMic(policy, [micUser("com.example.SomeRandomApp", name: "Random")])
    clock.advance(MeetingPolicy.micDebounce + 10)
    policy.reevaluate()
    #expect(policy.reason == nil)
    #expect(policy.hint == nil)
}

@Test @MainActor func dictationAppProducesHintNotPause() {
    let (policy, clock) = makePolicy()
    setMic(policy, [micUser("com.superwhisper.app", name: "superwhisper")])
    clock.advance(MeetingPolicy.micDebounce + 10)
    policy.reevaluate()
    #expect(policy.reason == nil)
    #expect(policy.hint == .dictating)
}

@Test @MainActor func excludedAppIsIgnoredEvenThoughItIsAConferencingApp() {
    let (policy, clock) = makePolicy { $0.meetingExcludedApps = ["us.zoom.xos"] }
    setMic(policy, [micUser("us.zoom.xos")])
    clock.advance(MeetingPolicy.micDebounce + 10)
    policy.reevaluate()
    #expect(policy.reason == nil)
}

@Test @MainActor func microphoneIgnoredWhenMeetingUsesMicrophoneIsOff() {
    let (policy, clock) = makePolicy { $0.meetingUsesMicrophone = false }
    setMic(policy, [micUser("us.zoom.xos")])
    clock.advance(MeetingPolicy.micDebounce + 10)
    policy.reevaluate()
    #expect(policy.reason == nil)
}

@Test @MainActor func pauseOnMeetingOffSuppressesTheReasonButKeepsTheDictationHint() {
    let (policy, clock) = makePolicy { $0.pauseOnMeeting = false }
    setMic(policy, [micUser("us.zoom.xos"), micUser("com.superwhisper.app")])
    clock.advance(MeetingPolicy.micDebounce + 10)
    policy.reevaluate()
    #expect(policy.reason == nil)
    #expect(policy.hint == .dictating)
}

@Test @MainActor func cameraShortCircuitsTheMicDebounce() {
    let (policy, _) = makePolicy()
    setMic(policy, [micUser("us.zoom.xos")])
    #expect(policy.reason == nil)
    policy.update(cameraInUse: true)
    #expect(policy.reason != nil, "camera evidence must not wait for the mic debounce")
}

// MARK: - Bundle matching

@Test func bundleMatchingIsCaseInsensitiveAndHelperAware() {
    #expect(BundleMatch.matches("com.tinyspeck.slackmacgap.helper", entry: "com.tinyspeck.slackmacgap"))
    #expect(BundleMatch.matches("US.ZOOM.XOS", entry: "us.zoom.xos"))
    #expect(!BundleMatch.matches("com.microsoft.teams2", entry: "com.microsoft.teams"))
    #expect(!BundleMatch.matches(nil, entry: "com.foo"))
    #expect(!BundleMatch.matches("", entry: "com.foo"))
}

@Test func knownBundlesClassification() {
    #expect(KnownBundles.isConferencing("us.zoom.xos"))
    #expect(KnownBundles.isConferencing("com.microsoft.teams2"))
    #expect(KnownBundles.isConferencing("com.cisco.webexmeetingsapp"))   // substring rule
    #expect(KnownBundles.isMeetingCapable("company.thebrowser.Browser"))
    #expect(!KnownBundles.isMeetingCapable("com.apple.TextEdit"))
    #expect(KnownBundles.isCaffeinator(bundleID: nil, processName: "caffeinate"))
    #expect(KnownBundles.isCaffeinator(bundleID: "com.if.Amphetamine", processName: nil))
    #expect(!KnownBundles.isCaffeinator(bundleID: "com.apple.Safari", processName: "Safari"))
}

// MARK: - Fullscreen geometry

@Test func fullscreenGeometryMatchesTheMenuBarInsetShape() {
    let display = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    // Measured live: both native fullscreen and a maximised window report this.
    #expect(FullscreenGeometry.isApproximately(CGRect(x: 0, y: 39, width: 1800, height: 1130), display))
    #expect(FullscreenGeometry.isApproximately(display, display))
    #expect(!FullscreenGeometry.isApproximately(CGRect(x: 0, y: 39, width: 1800, height: 800), display))
    #expect(!FullscreenGeometry.isApproximately(CGRect(x: 100, y: 200, width: 900, height: 600), display))
}

// MARK: - Dictation-aware deferral: the merge ActivityMonitor publishes to the engine

@Test @MainActor func dictationHintIsReportedEvenWhenInputDetectionIsDisarmed() {
    // The typing/dragging detector only runs in the last seconds before a break, so `input` is nil
    // most of the time. Dictation comes from the mic instead and must survive that.
    #expect(ActivityMonitor.mergedHint(meeting: .dictating, input: nil, deferWhileTyping: true) == .dictating)
    #expect(ActivityMonitor.mergedHint(meeting: .dictating, input: nil, deferWhileTyping: false) == .dictating)
}

@Test @MainActor func typingHintOnlySurvivesWhileTypingDeferralIsOn() {
    #expect(ActivityMonitor.mergedHint(meeting: nil, input: .typing, deferWhileTyping: true) == .typing)
    #expect(ActivityMonitor.mergedHint(meeting: nil, input: .typing, deferWhileTyping: false) == nil)
    #expect(ActivityMonitor.mergedHint(meeting: nil, input: nil, deferWhileTyping: true) == nil)
}

@Test @MainActor func dictationOutranksTyping() {
    // Dictation apps type *for* you; the mic-borne hint is the more informative label.
    #expect(ActivityMonitor.mergedHint(meeting: .dictating, input: .typing, deferWhileTyping: true) == .dictating)
}

@Test @MainActor func dictationHintIsIndependentOfEveryPauseSwitch() {
    // pauseOnMeeting off, meetingUsesMicrophone off: neither is about dictation.
    let (policy, clock) = makePolicy {
        $0.pauseOnMeeting = false
        $0.meetingUsesMicrophone = false
        $0.deferWhileTyping = false
    }
    setMic(policy, [micUser("com.electron.wispr-flow.accessibility-mac-app", name: "Wispr Flow")])
    clock.advance(MeetingPolicy.micDebounce + 1)
    policy.reevaluate()
    #expect(policy.reason == nil)
    #expect(policy.hint == .dictating)
    #expect(ActivityMonitor.mergedHint(meeting: policy.hint, input: nil, deferWhileTyping: false) == .dictating)
}
