// TGMenuBar — Settings ▸ Alerts & Nudges. The warning shots before a break.
import SwiftUI
import TGCore

struct AlertsPage: View {

    @ObservedObject var store: SettingsStore

    private var settings: TGCore.Settings { store.settings }

    var body: some View {
        Form {
            Section {
                Picker("Warn me before a break", selection: $store.settings.preBreakWarningSeconds) {
                    Text("30 sec").tag(TimeInterval(30))
                    Text("1 min").tag(TimeInterval(60))
                    Text("90 sec").tag(TimeInterval(90))
                    Text("2 min").tag(TimeInterval(120))
                }
                DurationPicker(
                    title: "Keep the card on screen for",
                    value: $store.settings.preBreakCardVisibleSeconds,
                    presets: [5, 10, 15, 30],
                    unit: .seconds,
                    bounds: 2...120
                )
                LabeledContent("Summary", value: warningSummary)
            } header: {
                Text("Pre-break card")
            } footer: {
                Text("The card offers Start now, +1m, +5m and +15m. It never takes focus and it never blocks a click.")
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
