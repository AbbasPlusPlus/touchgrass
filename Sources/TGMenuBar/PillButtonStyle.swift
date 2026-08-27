// TGMenuBar — the small capsule buttons in the quick panel's action row.
import SwiftUI

/// A compact capsule button. `prominent` marks the primary action ("Start break"), which is
/// also the one allowed to take the leftover width — the `+1m`/`+5m`/`Skip` pills hug their
/// labels so the primary label never has to truncate.
struct PillButtonStyle: ButtonStyle {
    var prominent: Bool = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.vertical, 6)
            .padding(.horizontal, prominent ? 12 : 10)
            .frame(maxWidth: prominent ? .infinity : nil)
            .fixedSize(horizontal: !prominent, vertical: false)
            .foregroundStyle(foreground)
            .background(
                Capsule(style: .continuous)
                    .fill(background(pressed: configuration.isPressed))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(prominent ? 0 : 0.10), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule(style: .continuous))
    }

    private var foreground: Color {
        prominent ? .white : .primary
    }

    private func background(pressed: Bool) -> Color {
        if prominent { return Color.accentColor.opacity(pressed ? 0.75 : 1) }
        return Color.primary.opacity(pressed ? 0.16 : 0.07)
    }
}
