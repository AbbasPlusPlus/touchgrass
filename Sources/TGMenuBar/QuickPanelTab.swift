// TGMenuBar — the two faces of the quick panel.
import SwiftUI

/// "Now" is the countdown and the buttons; "Stats" is rest, rhythm and where the time went.
public enum QuickPanelTab: String, CaseIterable, Hashable, Sendable {
    case now
    case stats

    public var title: String {
        switch self {
        case .now: return "Now"
        case .stats: return "Stats"
        }
    }
}

/// The segmented control in the panel's header.
///
/// Hand-rolled rather than `Picker(.segmented)`: on glass, AppKit's segmented control brings its
/// own opaque bezel and its own idea of the accent colour, and both fight the panel.
struct QuickPanelTabControl: View {

    @Binding var tab: QuickPanelTab

    @State private var hovered: QuickPanelTab?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(QuickPanelTab.allCases, id: \.self) { item in
                Button { tab = item } label: {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(tab == item ? TGPalette.onMatcha : TGPalette.ink2)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 15)
                        .background(
                            Capsule(style: .continuous).fill(fill(item))
                        )
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(TGPalette.hoverAnimation()) { hovered = hovering ? item : nil }
                }
                .accessibilityAddTraits(tab == item ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(2)
        .background(Capsule(style: .continuous).fill(TGPalette.paper2.opacity(0.34)))
        .overlay(Capsule(style: .continuous).strokeBorder(TGPalette.stone.opacity(0.8), lineWidth: 1))
    }

    private func fill(_ item: QuickPanelTab) -> Color {
        if tab == item { return TGPalette.matcha }
        return hovered == item ? TGPalette.stone.opacity(0.40) : .clear
    }
}
