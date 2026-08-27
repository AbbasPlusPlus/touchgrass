// TGMenuBar — Settings ▸ Smart Pause. When TouchGrass should get out of the way.
import SwiftUI
import TGCore

struct SmartPausePage: View {

    @ObservedObject var store: SettingsStore

    private var settings: TGCore.Settings { store.settings }

    var body: some View {
        Form {
            meetingsSection
            videoSection
            appsSection
            idleSection
            activitySection
        }
        .formStyle(.grouped)
    }

    // MARK: - Meetings

    private var meetingsSection: some View {
        Section {
            Toggle("Pause during calls and meetings", isOn: $store.settings.pauseOnMeeting)
            if settings.pauseOnMeeting {
                Toggle("Camera in use counts as a meeting", isOn: $store.settings.meetingUsesCamera)
                Toggle("Microphone in use counts as a meeting", isOn: $store.settings.meetingUsesMicrophone)
                LabeledContent("Detecting by", value: meetingMethodSummary)

                AppListEditor(
                    title: "Never treat as a meeting",
                    footnote: "Audio tools and virtual devices that hold the mic open.",
                    emptyMessage: "Every app can trigger meeting detection.",
                    bundleIDs: $store.settings.meetingExcludedApps
                )

                AppListEditor(
                    title: "Dictation apps",
                    footnote: "Mic use by these apps delays a break instead of pausing the timer.",
                    emptyMessage: "No dictation apps listed.",
                    bundleIDs: $store.settings.dictationApps
                )
            }
        } header: {
            Text("Meetings")
        } footer: {
            Text("Detected from camera and microphone in-use flags — no permission prompt, no orange dot, and TouchGrass never sees or hears anything.")
        }
    }

    private var meetingMethodSummary: String {
        switch (settings.meetingUsesCamera, settings.meetingUsesMicrophone) {
        case (true, true): return "Camera or microphone"
        case (true, false): return "Camera only"
        case (false, true): return "Microphone only"
        case (false, false): return "Nothing selected"
        }
    }

    // MARK: - Video

    private var videoSection: some View {
        Section("Video") {
            Toggle("Pause while a video is playing", isOn: $store.settings.pauseOnVideo)
            if settings.pauseOnVideo {
                Toggle("Only when the video is in front", isOn: $store.settings.videoFrontmostOnly)
                AppListEditor(
                    title: "Never treat as video",
                    footnote: "Editors and music apps that hold a display-sleep assertion all day.",
                    emptyMessage: "No exclusions.",
                    bundleIDs: $store.settings.videoExcludedApps
                )
            }
        }
    }

    // MARK: - Apps

    private var appsSection: some View {
        Section {
            Toggle("Pause during fullscreen games", isOn: $store.settings.pauseOnFullscreen)
            Text("Detected automatically. To pause for other fullscreen apps, add them to Deep Focus Apps.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Pause while a macOS Focus is on", isOn: $store.settings.pauseOnFocusMode)

            AppListEditor(
                title: "Deep focus apps",
                footnote: "Work you shouldn't be pulled out of.",
                emptyMessage: "No deep focus apps yet.",
                bundleIDs: $store.settings.deepFocusApps
            )
            Picker("Pause deep focus apps", selection: $store.settings.deepFocusMode) {
                ForEach(DeepFocusMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        } header: {
            Text("Apps")
        } footer: {
            Text("Detection uses window geometry and app metadata only — it needs no Screen Recording permission.")
        }
    }

    // MARK: - Idle

    private var idleSection: some View {
        Section {
            DurationPicker(
                title: "Pause after no input for",
                value: $store.settings.idlePauseAfter,
                presets: [1, 2, 3, 5].map { $0 * 60 },
                unit: .minutes,
                bounds: 1...60
            )
            DurationPicker(
                title: "Reset the timer after",
                value: $store.settings.idleResetAfter,
                presets: [5, 10, 15, 30].map { $0 * 60 },
                unit: .minutes,
                bounds: 1...240
            )
            LabeledContent("Away behaviour", value: idleSummary)
        } header: {
            Text("Away from the Mac")
        } footer: {
            Text("Stepping away already rests your eyes. A long enough absence counts as a break you've taken.")
        }
    }

    private var idleSummary: String {
        "Freeze after \(TGFormat.compact(settings.idlePauseAfter)), count as a break after \(TGFormat.compact(settings.idleResetAfter))"
    }

    // MARK: - Activity

    private var activitySection: some View {
        Section {
            Toggle("Wait if I'm typing or dragging", isOn: $store.settings.deferWhileTyping)
            if settings.deferWhileTyping {
                DurationPicker(
                    title: "Then wait a further",
                    value: $store.settings.typingBufferSeconds,
                    presets: [0, 2, 3, 5, 10],
                    unit: .seconds,
                    bounds: 0...60
                )
            }
            DurationPicker(
                title: "Cooldown after a call or video",
                value: $store.settings.cooldownAfterActivity,
                presets: [0, 60, 120, 300],
                unit: .seconds,
                bounds: 0...900
            )
        } header: {
            Text("Interruption guard")
        } footer: {
            Text("A break that lands mid-sentence is the interruption this app exists to avoid.")
        }
    }
}
