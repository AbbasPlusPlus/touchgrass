// TGMenuBar — Settings ▸ Appearance. What you see when a break starts.
import SwiftUI
import TGCore

struct AppearancePage: View {

    @ObservedObject var store: SettingsStore

    private var settings: TGCore.Settings { store.settings }

    var body: some View {
        Form {
            Section {
                BackgroundPicker(background: $store.settings.background)
            } header: {
                Text("Break background")
            } footer: {
                Text(backgroundSummary)
            }

            Section("On screen") {
                Toggle("Show the clock", isOn: $store.settings.showClock)
                Toggle("Show the title", isOn: $store.settings.showTitle)
                Toggle("Show the subtitle", isOn: $store.settings.showSubtitle)
            }

            Section {
                MessageListEditor(
                    title: "Short break messages",
                    footnote: "One is picked at random each break.",
                    messages: $store.settings.shortBreakMessages
                )
            } header: {
                Text("Messages")
            }

            Section {
                MessageListEditor(
                    title: "Long break messages",
                    messages: $store.settings.longBreakMessages
                )
            }
        }
        .formStyle(.grouped)
    }

    private var backgroundSummary: String {
        switch settings.background {
        case .screenBlur: return "Softly blurs whatever you were doing."
        case .wallpaper: return "Your own desktop picture, blurred, on every display."
        case .gradient(let preset): return "\(PresetPalette.title(preset)) gradient."
        case .animated(let preset): return "\(PresetPalette.title(preset)), animated on the main display."
        case .image(let path): return URL(fileURLWithPath: path).lastPathComponent
        }
    }
}
