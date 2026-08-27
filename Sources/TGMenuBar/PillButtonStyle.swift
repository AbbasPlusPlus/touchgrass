// TGMenuBar — the small capsule buttons in the quick panel's action row.
import AppKit
import SwiftUI

/// A compact capsule button in two tiers, both hugging their label so the row can be centred.
///
/// `.primary` is the one thing the panel wants you to do ("Break now" / "Resume"): a matcha
/// fill with paper type, the only saturated thing on the panel. `.quiet` is for the pills
/// under it — translucent paper with a stone hairline, so they read as chrome rather than as
/// three more decisions.
///
/// `fullWidth` swaps the hug for a stretch: the Now tab stacks its pills in a fixed-width
/// column, where three capsules of three different widths would read as debris.
struct PillButtonStyle: ButtonStyle {

    enum Tier {
        case primary
        case quiet
    }

    var tier: Tier = .quiet
    /// Fill the width offered instead of hugging the label.
    var fullWidth: Bool = false

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(tier == .primary ? TGType.pill : TGType.pillQuiet)
            .lineLimit(1)
            .minimumScaleFactor(fullWidth ? 0.82 : 1)
            .fixedSize(horizontal: !fullWidth, vertical: true)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 8)
            .padding(.horizontal, tier == .primary ? 15 : 12)
            .foregroundStyle(tier == .primary ? TGPalette.onMatcha : TGPalette.ink)
            .background(
                Capsule(style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tier == .primary ? Color.clear : TGPalette.stone,
                                  lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule(style: .continuous))
            .onHover { hovering in
                withAnimation(TGPalette.hoverAnimation()) { isHovered = hovering && isEnabled }
            }
    }

    private func fill(pressed: Bool) -> Color {
        switch tier {
        case .primary:
            // Matcha holds its hue; the tiers of state are brightness, not opacity.
            return pressed ? TGPalette.matchaDeep : TGPalette.matcha.opacity(isHovered ? 0.86 : 1)
        case .quiet:
            let paper = TGPalette.paper2
            if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency { return paper }
            return paper.opacity(pressed ? 0.85 : (isHovered ? 0.62 : 0.40))
        }
    }
}
