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
                CustomReminderListEditor(reminders: $store.settings.customReminders)
            } header: {
                Text("Custom reminders")
            } footer: {
                Text("Water, stretch, eye drops — anything you want a two-second tap on the shoulder about. Like blink and posture they run on real time: they keep counting through meetings and hold only while a break is on screen.")
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
        .onAppear { seedExamplesIfNeeded() }
    }

    // MARK: - First-run examples

    /// Three *disabled* examples so an empty section isn't a dead end. Seeded once, ever: deleting
    /// them is a decision, and a deleted example that comes back is a bug.
    private static let seedDefaultsKey = "TouchGrass.didSeedCustomReminders"

    private func seedExamplesIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.seedDefaultsKey) else { return }
        defaults.set(true, forKey: Self.seedDefaultsKey)
        guard store.settings.customReminders.isEmpty else { return }
        store.settings.customReminders = ReminderSymbols.examples()
    }

    private var nextUpSummary: String {
        var parts: [String] = []
        if settings.blinkRemindersEnabled {
            parts.append("Blink every \(TGFormat.compact(settings.blinkReminderInterval))")
        }
        if settings.postureRemindersEnabled {
            parts.append("posture every \(TGFormat.compact(settings.postureReminderInterval))")
        }
        let custom = settings.customReminders.filter(\.enabled).count
        if custom > 0 {
            parts.append("\(custom) custom \(custom == 1 ? "reminder" : "reminders")")
        }
        return parts.isEmpty ? "Nothing scheduled" : parts.joined(separator: ", ")
    }
}
