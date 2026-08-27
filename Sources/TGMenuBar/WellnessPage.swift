// TGMenuBar — Settings ▸ Wellness. The small nudges between breaks.
import SwiftUI
import TGCore

struct WellnessPage: View {

    @ObservedObject var store: SettingsStore

    private var settings: TGCore.Settings { store.settings }

    var body: some View {
        Form {
            Section {
                Toggle("Remind me to blink", isOn: $store.settings.blinkRemindersEnabled)
                if settings.blinkRemindersEnabled {
                    DurationPicker(
                        title: "Blink reminder every",
                        value: $store.settings.blinkReminderInterval,
                        presets: [5, 10, 15, 20, 30].map { $0 * 60 },
                        unit: .minutes,
                        bounds: 1...120
                    )
                }
            } header: {
                Text("Blink")
            } footer: {
                Text("Staring at a screen roughly halves how often you blink. A two-second reminder is usually enough.")
            }

            Section("Posture") {
                Toggle("Remind me to sit up", isOn: $store.settings.postureRemindersEnabled)
                if settings.postureRemindersEnabled {
                    DurationPicker(
                        title: "Posture reminder every",
                        value: $store.settings.postureReminderInterval,
                        presets: [10, 20, 30, 45, 60].map { $0 * 60 },
                        unit: .minutes,
                        bounds: 1...180
                    )
                }
            }

            Section {
                Toggle("Dim the screen behind reminders", isOn: $store.settings.wellnessDimsScreen)
                Toggle("Show on the main display only", isOn: $store.settings.wellnessMainScreenOnly)
                LabeledContent("Next up", value: nextUpSummary)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Reminders float above your work for a couple of seconds and never take focus.")
            }
        }
        .formStyle(.grouped)
    }

    private var nextUpSummary: String {
        var parts: [String] = []
        if settings.blinkRemindersEnabled {
            parts.append("Blink every \(TGFormat.compact(settings.blinkReminderInterval))")
        }
        if settings.postureRemindersEnabled {
            parts.append("posture every \(TGFormat.compact(settings.postureReminderInterval))")
        }
        return parts.isEmpty ? "Nothing scheduled" : parts.joined(separator: ", ")
    }
}
