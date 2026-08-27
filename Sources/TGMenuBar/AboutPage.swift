// TGMenuBar — Settings ▸ About.
import AppKit
import SwiftUI

struct AboutPage: View {

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    appIcon
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TouchGrass")
                            .font(TGType.heading)
                        Text(Self.versionLine)
                            .font(TGType.footnote)
                            .foregroundStyle(.secondary)
                        Text("Breaks that never become the interruption.")
                            .font(TGType.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            }

            Section("Links") {
                link("Source code", "https://github.com/AbbasPlusPlus/touchgrass", symbol: "chevron.left.forwardslash.chevron.right")
                link("Report an issue", "https://github.com/AbbasPlusPlus/touchgrass/issues", symbol: "exclamationmark.bubble")
            }

            Section {
                LabeledContent("Permissions", value: "None required")
                LabeledContent("Copyright", value: Self.copyright)
            } header: {
                Text("Details")
            } footer: {
                Text("TouchGrass never asks for Screen Recording or Accessibility, and it doesn't read your camera or microphone — only whether something else is using them.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Pieces

    private var appIcon: some View {
        Group {
            // Outside a real .app bundle `applicationIconImage` is a generic alias icon, which
            // looks broken — fall back to the leaf instead.
            if Bundle.main.bundleIdentifier != nil, let icon = NSApp.applicationIconImage {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "leaf.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .foregroundStyle(.green)
            }
        }
        .frame(width: 64, height: 64)
    }

    private func link(_ title: String, _ urlString: String, symbol: String) -> some View {
        LabeledContent {
            Button {
                guard let url = URL(string: urlString) else { return }
                NSWorkspace.shared.open(url)
            } label: {
                HStack(spacing: 3) {
                    Text("Open")
                    Image(systemName: "arrow.up.right")
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
            }
        }
    }

    // MARK: - Bundle info

    private static var versionLine: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else { return "Development build" }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "Version \(version) (\($0))" } ?? "Version \(version)"
    }

    private static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "© 2026 Abbas"
    }
}
