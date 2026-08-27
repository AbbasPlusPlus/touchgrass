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
                            .foregroundStyle(TGPalette.ink)
                        Text(Self.versionLine)
                            .font(TGType.footnote)
                            .foregroundStyle(TGPalette.ink2)
                        Text("Breaks that never become the interruption.")
                            .font(TGType.caption)
                            .foregroundStyle(TGPalette.ink2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            }

        }
        .formStyle(.grouped)
    }

    // MARK: - Pieces

    /// The mark itself rather than `NSApp.applicationIconImage`: it is vector, it is right
    /// outside a real .app bundle (where the icon is a generic alias), and it is the same five
    /// paths the app icon is cut from.
    private var appIcon: some View {
        LogoMark()
            .frame(width: 64, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(TGPalette.paper2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(TGPalette.stone, lineWidth: 1)
            )
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
                    .foregroundStyle(TGPalette.matcha)
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
