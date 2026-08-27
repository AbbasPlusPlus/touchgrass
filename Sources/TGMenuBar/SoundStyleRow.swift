// TGMenuBar — one selectable style in Settings ▸ Sounds ▸ Style.
import SwiftUI
import TGCore

/// Title, a one-line note on the character of the sound, and a ▶ that auditions
/// it without selecting it.
///
/// A `Picker` was the obvious control and the wrong one: a sound you can't hear
/// before you commit to it is a word, not a choice. Rows let the ear decide.
struct SoundStyleRow: View {

    let style: SoundStyle
    let isSelected: Bool
    let select: () -> Void
    let preview: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: select) {
                HStack(spacing: 9) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? TGPalette.matcha : TGPalette.ink2)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(style.title)
                            .font(TGType.row)
                            .foregroundStyle(TGPalette.ink)
                        Text(style.subtitle)
                            .font(TGType.footnote)
                            .foregroundStyle(TGPalette.ink2)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: preview) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .frame(width: 22, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            // "None" has nothing to audition; the slot stays reserved so the
            // rows don't shuffle when the list is scanned.
            .disabled(style == SoundStyle.none)
            .opacity(style == SoundStyle.none ? 0 : 1)
            .help("Preview \(style.title)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? TGPalette.matcha.opacity(0.14)
                                 : (hovering ? TGPalette.stone.opacity(0.35) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? TGPalette.matcha.opacity(0.55) : Color.clear,
                              lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(TGPalette.hoverAnimation()) { self.hovering = hovering }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(style.title). \(style.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
