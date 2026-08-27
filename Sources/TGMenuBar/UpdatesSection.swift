// TGMenuBar — Settings ▸ General ▸ Updates. One row, two states: "Check Now" or "Restart".
import SwiftUI
import TGCore
import TGUpdate

/// Lives in its own file so `GeneralPage` only gains a single line. Reads `UpdateChecker.shared`
/// (passed in by the caller from a main-actor context) rather than being threaded through
/// `SettingsView` and `SettingsWindowController`.
struct UpdatesSection: View {

    @ObservedObject var store: SettingsStore
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        Section {
            Toggle("Check for updates automatically", isOn: automaticBinding)

            LabeledContent {
                HStack(spacing: 8) {
                    if case .downloading(let fraction) = updates.state {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .frame(width: 88)
                    } else if updates.state.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    actionButton
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version \(updates.currentVersionDescription)")
                    Text(statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let notes = releaseNotes {
                Text(notes)
                    .font(.system(size: 11))
                    .foregroundStyle(TGPalette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("TouchGrass downloads updates from its releases repository over HTTPS and checks each one against a SHA-256 checksum before installing. Your current version stays put until the new one is verified.")
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var actionButton: some View {
        if case .readyToInstall = updates.state {
            Button("Restart to update") { updates.installAndRelaunch() }
                .buttonStyle(.borderedProminent)
        } else {
            Button("Check Now") { updates.checkNow() }
                .disabled(updates.state.isBusy)
        }
    }

    private var automaticBinding: Binding<Bool> {
        Binding(
            get: { store.settings.autoUpdateEnabled },
            set: { enabled in
                store.settings.autoUpdateEnabled = enabled
                // Keep the live checker honest even before the app's settings sink runs.
                updates.automaticChecksEnabled = enabled
            }
        )
    }

    private var isError: Bool {
        if case .error = updates.state { return true }
        return false
    }

    private var releaseNotes: String? {
        guard case .readyToInstall(let release) = updates.state else { return nil }
        guard let notes = release.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else { return nil }
        return notes
    }

    private var statusLine: String {
        switch updates.state {
        case .idle:
            return lastCheckDescription
        case .checking:
            return "Checking…"
        case .upToDate:
            return "Up to date" + (lastCheckSuffix.map { " · \($0)" } ?? "")
        case .available(let release):
            return "Version \(release.displayVersion) is available"
        case .downloading(let fraction):
            return "Downloading… \(Int((fraction * 100).rounded()))%"
        case .readyToInstall(let release):
            return "Version \(release.displayVersion) is ready — restart to finish"
        case .error(let message):
            return message
        }
    }

    private var lastCheckDescription: String {
        lastCheckSuffix.map { "Last checked \($0)" } ?? "Not checked yet"
    }

    private var lastCheckSuffix: String? {
        guard let date = updates.lastCheck else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
