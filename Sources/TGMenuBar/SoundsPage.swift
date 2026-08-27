// TGMenuBar — Settings ▸ Sounds. Quiet by default; a soft exhale, not an alarm.
import SwiftUI
import TGCore

struct SoundsPage: View {

    @ObservedObject var store: SettingsStore
    /// Injected by the app so TGMenuBar never has to link TGAudio.
    let previewSound: (SoundStyle, String) -> Void

    private var settings: TGCore.Settings { store.settings }

    var body: some View {
        Form {
            Section {
                soundToggle("When a break starts", isOn: $store.settings.soundOnBreakStart, event: "start")
                soundToggle("When a break ends", isOn: $store.settings.soundOnBreakEnd, event: "end")
                soundToggle("When a break is coming up", isOn: $store.settings.soundOnPreBreak, event: "preBreak")
            } header: {
                Text("Play a sound")
            } footer: {
                Text("Every sound is a single soft tone. Nothing repeats and nothing insists.")
            }

            Section {
                Picker("Sound", selection: $store.settings.soundStyle) {
                    ForEach(SoundStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                LabeledContent("Volume") {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker").foregroundStyle(.secondary)
                        Slider(value: $store.settings.volume, in: 0...1)
                            .frame(width: 150)
                        Image(systemName: "speaker.wave.3").foregroundStyle(.secondary)
                        Text("\(Int(settings.volume * 100))%")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            } header: {
                Text("Style")
            } footer: {
                Text(styleSummary)
            }
        }
        .formStyle(.grouped)
    }

    private func soundToggle(_ title: String, isOn: Binding<Bool>, event: String) -> some View {
        HStack {
            Toggle(title, isOn: isOn)
            Spacer(minLength: 8)
            Button {
                previewSound(settings.soundStyle, event)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .frame(width: 20, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.leading, 6)
            .disabled(settings.soundStyle == .none)
            .help("Preview")
        }
    }

    private var styleSummary: String {
        settings.soundStyle == .none
            ? "Silent."
            : "\(settings.soundStyle.title) at \(Int(settings.volume * 100))%."
    }
}
