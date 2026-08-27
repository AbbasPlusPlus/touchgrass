// TGMenuBar — the settings window's left column.
import SwiftUI

/// Grouped sections with colored rounded-square icons, exactly the System Settings idiom.
struct SettingsSidebar: View {

    @Binding var selection: SettingsSection

    var body: some View {
        List(selection: optionalSelection) {
            ForEach(Array(SettingsSection.groups.enumerated()), id: \.offset) { _, group in
                if group.header.isEmpty {
                    ForEach(group.sections) { row($0) }
                } else {
                    Section(group.header) {
                        ForEach(group.sections) { row($0) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(TGPalette.paper)
    }

    private func row(_ section: SettingsSection) -> some View {
        Label {
            Text(section.title)
                .foregroundStyle(TGPalette.ink)
        } icon: {
            SettingsIcon(symbol: section.symbol, tint: section.tint)
        }
        .tag(section)
    }

    /// `List` wants an optional selection; the window always has a page open.
    private var optionalSelection: Binding<SettingsSection?> {
        Binding(
            get: { selection },
            set: { if let new = $0 { selection = new } }
        )
    }
}
