// TGMenuBar — one line of the quick panel's inset list.
import SwiftUI

/// An emoji, a label, and a live value. Each row draws its own rounded card so the list reads
/// as two calm blocks rather than as a table.
///
/// Emoji rather than a tinted SF Symbol: they're already beautifully drawn, instantly readable
/// at a glance, and they carry the personality the rest of this panel deliberately doesn't.
///
/// No hover state: these rows are facts, not controls, and lighting one under the pointer
/// would promise a click that never happens.
struct QuickPanelRow: View {

    let emoji: String
    let title: String
    /// Drawn in full-strength text before `value`, separated by a dot: "Short · 1 min".
    var accent: String?
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(emoji)
                .font(.system(size: 15))
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(title)
                .font(TGType.row)
                .foregroundStyle(TGPalette.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let accent {
                Text(accent)
                    .font(TGType.rowEmphasis)
                    .foregroundStyle(TGPalette.ink)
                Text("·")
                    .font(TGType.row)
                    .foregroundStyle(TGPalette.ink2)
            }
            Text(value)
                .font(TGType.row)
                .foregroundStyle(TGPalette.ink2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: TGType.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(TGPalette.rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(TGPalette.stone.opacity(0.7), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
