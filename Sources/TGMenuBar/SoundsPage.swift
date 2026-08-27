// TGMenuBar — Settings ▸ Sounds. Quiet by default; a soft exhale, not an alarm.
import AppKit
import SwiftUI
import TGCore
import UniformTypeIdentifiers

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
                            .font(TGType.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("Style")
            } footer: {
                Text(styleSummary)
            }

            Section {
                customSoundRow
            } header: {
                Text("Your own sound")
            } footer: {
                Text(customSoundSummary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Custom sound

    private var customSoundRow: some View {
        LabeledContent("Custom sound") {
            HStack(spacing: 8) {
                Text(customSoundName)
                    .font(TGType.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button("Choose…") { chooseCustomSound() }
                    .controlSize(.small)

                if settings.customSoundPath != nil {
                    Button {
                        store.settings.customSoundPath = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Back to the built-in sounds")

                    Button {
                        previewSound(settings.soundStyle, "breakStart")
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                            .frame(width: 22, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(settings.soundStyle == .none)
                    .help("Preview")
                }
            }
        }
    }

    /// Non-sandboxed app: the panel hands back a plain path we can keep and read later.
    private func chooseCustomSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff, .mpeg4Audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Use Sound"
        panel.message = "Pick an audio file to play instead of the built-in sounds."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.settings.customSoundPath = url.path
        if settings.soundStyle == .none { store.settings.soundStyle = .bell }
    }

    private var customSoundName: String {
        guard let url = settings.customSoundURL else { return "Built-in" }
        return url.lastPathComponent
    }

    private var customSoundSummary: String {
        guard settings.customSoundURL != nil else {
            return "Pick any audio file — AIFF, WAV, CAF, M4A or MP3 — to use in place of the bundled tones."
        }
        return "Your file plays for every event. Clear it with × to go back to the built-in sounds."
    }

    private func soundToggle(_ title: String, isOn: Binding<Bool>, event: String) -> some View {
        HStack {
            Toggle(title, isOn: isOn)
            Spacer(minLength: 8)
            Button {
                previewSound(settings.soundStyle, event)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11))
                    .frame(width: 22, height: 18)
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
