// TGMenuBar — Settings ▸ Alerts & Nudges. The warning shots before a break.
import SwiftUI
import TGCore

struct AlertsPage: View {

    @ObservedObject var store: SettingsStore

    private var settings: TGCore.Settings { store.settings }

    var body: some View {
        Form {
            Section {
                Toggle("Show a pre-break notification", isOn: $store.settings.preBreakEnabled)
            } header: {
                Text("Pre-break notification")
            } footer: {
                Text("A dark banner grows out of the notch as a break approaches; the countdown drains around its edges. On displays without a notch it appears at the top centre.")
            }

            if settings.preBreakEnabled {
                Section {
                    Picker("Warn me before a break", selection: $store.settings.preBreakWarningSeconds) {
                        Text("30 sec").tag(TimeInterval(30))
                        Text("1 min").tag(TimeInterval(60))
                        Text("90 sec").tag(TimeInterval(90))
                        Text("2 min").tag(TimeInterval(120))
                    }
                    DurationPicker(
                        title: "Keep it on screen for",
                        value: $store.settings.preBreakCardVisibleSeconds,
                        presets: [5, 10, 15, 30],
                        unit: .seconds,
                        bounds: 2...120
                    )
                    LabeledContent("Summary", value: warningSummary)
                } header: {
                    Text("Timing")
                } footer: {
                    Text("The banner offers Start, and snooze +1m / +5m / +15m. It never takes focus and it never blocks a click.")
                }
            }

            Section {
                Picker("Cursor countdown", selection: $store.settings.cursorCountdownSeconds) {
                    Text("Off").tag(0)
                    Text("Last 5 seconds").tag(5)
                    Text("Last 10 seconds").tag(10)
                }
                Toggle("Show the countdown on every display",
                       isOn: $store.settings.showCountdownOnAllDisplays)
            } header: {
                Text("Final seconds")
            } footer: {
                Text(settings.cursorCountdownSeconds == 0
                     ? "No pill follows the cursor."
                     : "A small pill follows your pointer for the last \(settings.cursorCountdownSeconds) seconds.")
            }
        }
        .formStyle(.grouped)
    }

    private var warningSummary: String {
        "\(TGFormat.compact(settings.preBreakWarningSeconds)) ahead, visible for \(TGFormat.compact(settings.preBreakCardVisibleSeconds))"
    }
}
