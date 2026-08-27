// TGMenuBar — Settings ▸ Screen Breaks. How often, how long, and how hard to insist.
import SwiftUI
import TGCore

struct ScreenBreaksPage: View {

    @ObservedObject var store: SettingsStore

    private var settings: TGCore.Settings { store.settings }

    var body: some View {
        Form {
            Section {
                DurationPicker(
                    title: "Break interval",
                    value: $store.settings.shortBreakInterval,
                    presets: [15, 20, 25, 30, 45, 60].map { $0 * 60 },
                    unit: .minutes,
                    bounds: 1...240
                )
                DurationPicker(
                    title: "Break duration",
                    value: $store.settings.shortBreakDuration,
                    presets: [15, 20, 30, 45, 60],
                    unit: .seconds,
                    bounds: 5...600
                )
            } header: {
                Text("Short breaks")
            } footer: {
                Text("Counted in focused screen time — the clock freezes while you're away or in a call.")
            }

            Section("Long breaks") {
                Toggle("Take a longer break now and then", isOn: $store.settings.longBreaksEnabled)
                if settings.longBreaksEnabled {
                    Picker("Long break every", selection: $store.settings.longBreakEvery) {
                        ForEach(2...8, id: \.self) { n in
                            Text("\(TGFormat.ordinal(n)) break").tag(n)
                        }
                    }
                    DurationPicker(
                        title: "Long break duration",
                        value: $store.settings.longBreakDuration,
                        presets: [2, 3, 5, 10].map { $0 * 60 },
                        unit: .minutes,
                        bounds: 1...60
                    )
                    LabeledContent("Cadence", value: cadenceSummary)
                }
            }

            Section {
                EnforcementPicker(enforcement: $store.settings.enforcement)
                if settings.enforcement == .balanced {
                    DurationPicker(
                        title: "Skip unlocks after",
                        value: $store.settings.balancedSkipDelaySeconds,
                        presets: [3, 5, 10, 15],
                        unit: .seconds,
                        bounds: 1...60
                    )
                }
            } header: {
                Text("Break enforcement")
            } footer: {
                Text(enforcementFootnote)
            }

            OfficeHoursSection(store: store)

            SkipLimitsSection(store: store)

            Section {
                counter("Snoozes per day", value: $store.settings.snoozesPerDay, range: 0...50)
                counter("Snoozes per session", value: $store.settings.snoozesPerSession, range: 0...20)
            } header: {
                Text("Snoozes")
            } footer: {
                Text("A snooze pushes the break back a minute or five. Running out is the point.")
            }

            Section("During a break") {
                Toggle("Let me end a long break early once it's nearly done",
                       isOn: endBreakEarlyBinding)
                Picker("Double-press Escape", selection: $store.settings.doubleEscapeSkips) {
                    Text("Skips the break").tag(true)
                    Text("Snoozes 5 minutes").tag(false)
                }
                Toggle("Lock my Mac when a break starts", isOn: $store.settings.lockScreenOnBreakStart)
            }
        }
        .formStyle(.grouped)
    }

    /// A number with a stepper, right-aligned like every other value on the page.
    private func counter(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text("\(value.wrappedValue)")
                    .monospacedDigit()
                Stepper("", value: value, in: range)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Derived copy

    /// Spells out the consequence rather than repeating the card's own subtitle.
    private var enforcementFootnote: String {
        switch settings.enforcement {
        case .casual:
            return "Skip is available the moment the break appears. Good for days that can't be interrupted."
        case .balanced:
            return "Skip appears a few seconds in — long enough to notice you're on a break before you dismiss it."
        case .hardcore:
            return "No Skip button at all. You can still snooze from the pre-break card while snoozes remain."
        }
    }

    private var cadenceSummary: String {
        guard settings.longBreaksEnabled else { return "Short breaks only" }
        return "Every \(TGFormat.ordinal(settings.longBreakEvery)) break is a \(TGFormat.duration(settings.longBreakDuration)) long break"
    }

    /// `allowEndBreakEarlyAfterFraction` is a Double in the contract; 1.0 means "never".
    private var endBreakEarlyBinding: Binding<Bool> {
        Binding(
            get: { store.settings.allowEndBreakEarlyAfterFraction < 1.0 },
            set: { store.settings.allowEndBreakEarlyAfterFraction = $0 ? 0.8 : 1.0 }
        )
    }
}
