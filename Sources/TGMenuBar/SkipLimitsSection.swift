// TGMenuBar — Settings ▸ Screen Breaks ▸ Skips. How many breaks you're allowed to throw away.
import SwiftUI
import TGCore

/// Two budgets. *Advance skips* drop the next break before it ever appears — the honest version
/// of quitting the app for an hour. *Skips per day* caps the ordinary kind; 0 means uncapped,
/// which is the default because a cap you didn't ask for is just a locked door.
struct SkipLimitsSection: View {

    @ObservedObject var store: SettingsStore

    var body: some View {
        Section {
            Toggle("Let me skip a break before it starts", isOn: $store.settings.advanceSkipsEnabled)
            if store.settings.advanceSkipsEnabled {
                stepper(
                    "Advance skips per day",
                    value: $store.settings.advanceSkipsPerDay,
                    range: 1...20,
                    display: "\(store.settings.advanceSkipsPerDay)"
                )
            }
            stepper(
                "Skips per day",
                value: $store.settings.skipsPerDay,
                range: 0...50,
                display: store.settings.skipsPerDay == 0 ? "Unlimited" : "\(store.settings.skipsPerDay)"
            )
        } header: {
            Text("Skips")
        } footer: {
            Text(footnote)
        }
    }

    private func stepper(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        display: String
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text(display)
                    .monospacedDigit()
                Stepper("", value: value, in: range)
                    .labelsHidden()
            }
        }
    }

    private var footnote: String {
        guard store.settings.advanceSkipsEnabled else {
            return "Set a daily cap if breaks you skip have a way of becoming breaks you never take."
        }
        return "\"Skip next break\" appears in the menu bar's right-click menu while the timer is counting. Hardcore mode ignores both settings — it never skips."
    }
}
