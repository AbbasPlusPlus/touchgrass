// TGMenuBar — Settings ▸ Keyboard Shortcuts.
import SwiftUI
import TGCore

struct ShortcutsPage: View {

    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyAction.displayOrder, id: \.self) { action in
                    LabeledContent {
                        ShortcutRecorderView(hotkey: binding(for: action))
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: action.symbolName)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(action.title)
                                Text(action.subtitle)
                                    .font(TGType.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Global shortcuts")
            } footer: {
                Text("Shortcuts work from any app. They need at least one of ⌘, ⌃ or ⌥, and TouchGrass never asks for Accessibility access to read them.")
            }

            Section {
                LabeledContent("Recorded", value: "\(store.settings.hotkeys.count) of \(HotkeyAction.allCases.count)")
                Button("Clear all shortcuts") {
                    store.settings.hotkeys.removeAll()
                }
                .disabled(store.settings.hotkeys.isEmpty)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for action: HotkeyAction) -> Binding<Hotkey?> {
        Binding(
            get: { store.settings.hotkeys[action.rawValue] },
            set: { store.settings.hotkeys[action.rawValue] = $0 }
        )
    }
}
