// TGMenuBar — one swatch in the break-background picker.
import SwiftUI

/// A small preview tile with a selection ring and a caption underneath.
struct BackgroundTile: View {

    let caption: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> AnyView

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                content()
                    .frame(width: 64, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                          lineWidth: isSelected ? 2.5 : 1)
                    )
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(caption)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
