// TGOverlay — the pill buttons on the Dynamic-Island banner.
// Always dark (the banner is black whatever the system appearance), so this is a fixed-mode
// style rather than one built on the dynamic palette. Two tiers: a ghost snooze pill and the
// tinted matcha primary.

import SwiftUI

struct NotchPillStyle: ButtonStyle {

    var primary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        NotchPillBody(configuration: configuration, primary: primary)
    }
}

private struct NotchPillBody: View {
    let configuration: ButtonStyleConfiguration
    let primary: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(primary ? Color(red: 0.06, green: 0.086, blue: 0.047)
                                     : Color(white: 0.92))
            .padding(.horizontal, primary ? 16 : 12)
            .padding(.vertical, 8)
            .background(background)
            .overlay(
                Capsule().strokeBorder(primary ? Color.clear : Color.white.opacity(0.14),
                                       lineWidth: 1)
            )
            .clipShape(Capsule())
            .opacity(isEnabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(OverlayMotion.ease(0.14), value: configuration.isPressed)
            .animation(OverlayMotion.ease(0.12), value: hovering)
            .onHover { hovering = $0 && isEnabled }
            .contentShape(Capsule())
    }

    @ViewBuilder
    private var background: some View {
        if primary {
            Capsule().fill(hovering ? OverlayPalette.matchaOnDark.opacity(0.92)
                                    : OverlayPalette.matchaOnDark)
        } else {
            Capsule().fill(Color.white.opacity(hovering ? 0.16 : 0.08))
        }
    }
}
