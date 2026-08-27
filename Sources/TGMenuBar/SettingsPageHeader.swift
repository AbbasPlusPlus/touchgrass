// TGMenuBar — the title strip above each settings page.
import SwiftUI

/// Repeats the sidebar's icon and names the page, the way System Settings does above the form.
struct SettingsPageHeader: View {
    let section: SettingsSection
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(symbol: section.symbol, tint: section.tint, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(TGType.title)
                    .foregroundStyle(TGPalette.ink)
                Text(subtitle)
                    .font(TGType.caption)
                    .foregroundStyle(TGPalette.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TGPalette.paper)
    }
}
