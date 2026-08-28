// TGMenuBar — Settings ▸ General.
import AppKit
import SwiftUI
import TGCore
import TGUpdate

struct GeneralPage: View {

    @ObservedObject var store: SettingsStore
    @ObservedObject var loginItems: LoginItemManager

    let onShowOnboarding: () -> Void
    let onQuit: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Launch TouchGrass at login", isOn: launchAtLoginBinding)
                LabeledContent("Login item", value: loginItems.statusDescription)
                if let error = loginItems.lastError {
                    Text(error)
                        .font(TGType.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Startup")
            } footer: {
                Text("Managed by macOS. You can also turn this off in System Settings ▸ General ▸ Login Items.")
            }

            Section {
                Picker("Menu bar shows", selection: $store.settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { style in
                        Text(style.settingsTitle).tag(style)
                    }
                }
            } header: {
                Text("Menu bar")
            } footer: {
                Text(store.settings.menuBarStyle.settingsFootnote)
            }

            Section {
                Toggle("Track app usage", isOn: $store.settings.trackAppUsage)
            } header: {
                Text("Stats")
            } footer: {
                Text("Only the app in front is recorded, never window titles or web pages. Stays on this Mac.")
            }

            UpdatesSection(store: store, updates: UpdateChecker.shared)

            Section("Help") {
                Link(destination: URL(string: "https://github.com/AbbasPlusPlus/touchgrass/issues/new")!) {
                    Label("Report an issue", systemImage: "exclamationmark.bubble")
                }
                Link(destination: URL(string: "https://github.com/AbbasPlusPlus/touchgrass/discussions")!) {
                    Label("Ask a question or suggest a feature", systemImage: "lightbulb")
                }
            }

            Section("Getting started") {
                LabeledContent("Setup") {
                    Button("Show onboarding again", action: onShowOnboarding)
                }
            }

            Section {
                LabeledContent("TouchGrass") {
                    Button("Quit", action: onQuit)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItems.refresh() }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItems.isEnabled },
            set: { wanted in
                // Mirror whatever macOS actually did back into Settings.
                let achieved = loginItems.setEnabled(wanted)
                store.settings.launchAtLogin = achieved
            }
        )
    }
}

// MARK: - Display names for the shared MenuBarStyle contract

extension MenuBarStyle {
    var settingsTitle: String {
        switch self {
        case .iconOnly: return "Icon only"
        case .timeOnly: return "Countdown only"
        case .iconAndTime: return "Icon and countdown"
        }
    }

    var settingsFootnote: String {
        switch self {
        case .iconOnly: return "The quietest option — hover for the countdown."
        case .timeOnly: return "Just the digits, no glyph."
        case .iconAndTime: return "The glyph plus a live mm:ss countdown."
        }
    }
}
