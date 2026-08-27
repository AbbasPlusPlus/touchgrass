// TGMenuBar — the title strip above each settings page.
import SwiftUI

/// Repeats the sidebar's icon and names the page, the way System Settings does above the form.
struct SettingsPageHeader: View {
    let section: SettingsSection
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(symbol: section.symbol, tint: section.tint, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(section.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}
