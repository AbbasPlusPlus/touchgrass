// TGMenuBar — one swatch in the break-background picker.
import SwiftUI

/// A small preview tile with a selection ring and a caption underneath.
struct BackgroundTile: View {

    let caption: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> AnyView

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                content()
                    .frame(width: 78, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isSelected ? TGPalette.matcha : TGPalette.stone,
                                          lineWidth: isSelected ? 2.5 : 1)
                    )
                    // Hovering lifts the tile off the page by a point.
                    .shadow(color: TGPalette.ink.opacity(hovering ? 0.22 : 0),
                            radius: hovering ? 5 : 0, y: hovering ? 1 : 0)
                Text(caption)
                    .font(TGType.footnote)
                    .foregroundStyle(isSelected ? TGPalette.matcha : TGPalette.ink2)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(TGPalette.hoverAnimation()) { self.hovering = hovering }
        }
        .accessibilityLabel(caption)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
