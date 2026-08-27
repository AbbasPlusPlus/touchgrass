// TGMenuBar — the small capsule buttons in the quick panel's action row.
import SwiftUI

/// A compact capsule button in two tiers, both hugging their label so the row can be centred.
///
/// `.primary` is the one thing the panel wants you to do ("Start break" / "Resume"); `.quiet`
/// is for the delay pills beside it. Both are neutral fills rather than accent-coloured — on
/// glass, a saturated button shouts, and this panel is meant to be calm.
struct PillButtonStyle: ButtonStyle {

    enum Tier {
        case primary
        case quiet
    }

    var tier: Tier = .quiet

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(tier == .primary ? TGType.pill : TGType.pillQuiet)
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, 8)
            .padding(.horizontal, tier == .primary ? 15 : 12)
            .foregroundStyle(Color.primary)
            .background(
                Capsule(style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(tier == .primary ? 0 : 0.10), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule(style: .continuous))
    }

    private func fill(pressed: Bool) -> Color {
        switch tier {
        case .primary: return Color.primary.opacity(pressed ? 0.27 : 0.18)
        case .quiet:   return Color.primary.opacity(pressed ? 0.15 : 0.07)
        }
    }
}
