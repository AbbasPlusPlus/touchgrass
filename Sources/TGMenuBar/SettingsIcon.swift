// TGMenuBar — the colored rounded-square glyph used all over the settings sidebar.
import SwiftUI

/// System-Settings' signature icon: a tinted, softly graded rounded square with a white symbol.
struct SettingsIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.56, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: tint.opacity(0.25), radius: 1, y: 0.5)
            .accessibilityHidden(true)
    }
}
