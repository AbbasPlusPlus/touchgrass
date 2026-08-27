// TGMenuBar — the +/− list of bundle IDs used by every exclusion setting.
import AppKit
import SwiftUI

/// A bordered list of apps with real icons, a − on each row and a + that opens an app chooser.
struct AppListEditor: View {

    let title: String
    var footnote: String?
    var emptyMessage: String = "No apps yet."
    @Binding var bundleIDs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(TGType.caption)

            VStack(spacing: 0) {
                if bundleIDs.isEmpty {
                    Text(emptyMessage)
                        .font(TGType.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                } else {
                    ForEach(Array(bundleIDs.enumerated()), id: \.element) { index, bundleID in
                        row(bundleID)
                        if index < bundleIDs.count - 1 {
                            Divider().padding(.leading, 34)
                        }
                    }
                }
                Divider()
                controls
            }
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )

            if let footnote {
                Text(footnote)
                    .font(TGType.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Rows

    private func row(_ bundleID: String) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: AppInfo.icon(for: bundleID))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(AppInfo.name(for: bundleID))
                    .font(TGType.caption)
                if !AppInfo.isInstalled(bundleID) {
                    Text("Not installed")
                        .font(TGType.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            Text(bundleID)
                .font(TGType.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Button {
                bundleIDs.removeAll { $0 == bundleID }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove \(AppInfo.name(for: bundleID))")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Button(action: add) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add app…")
                }
                .padding(.horizontal, 6)
                .frame(height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add an app…")

            Spacer()
        }
        .font(TGType.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    // MARK: - Mutation

    private func add() {
        guard let bundleID = AppInfo.chooseApplication() else { return }
        guard !bundleIDs.contains(bundleID) else { return }
        bundleIDs.append(bundleID)
    }

}
