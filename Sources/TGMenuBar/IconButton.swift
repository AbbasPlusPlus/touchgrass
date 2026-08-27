// TGMenuBar — a bare SF Symbol that is also a button.
import SwiftUI

/// The gear, the calendar toggle, the month arrows: a glyph with no chrome until the pointer
/// arrives, when a circular paper wash appears behind it. 120 ms, and nothing at all under
/// Reduce Motion beyond the wash itself.
struct IconButton: View {

    let symbol: String
    let label: String
    var size: CGFloat = 13
    var help: String?
    /// Width of the button's hit area; the wash is a circle of `diameter + 8`.
    var diameter: CGFloat = 20
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isEnabled ? TGPalette.ink2 : TGPalette.ink2.opacity(0.35))
                .frame(width: diameter, height: 18)
                .background(
                    Circle()
                        .fill(hovering && isEnabled ? TGPalette.stone.opacity(0.55) : .clear)
                        .frame(width: diameter + 8, height: diameter + 8)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            withAnimation(TGPalette.hoverAnimation()) { self.hovering = hovering }
        }
        .help(help ?? label)
        .accessibilityLabel(label)
    }
}
