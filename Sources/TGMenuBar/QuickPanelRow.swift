// TGMenuBar — one line of the quick panel's inset list.
import SwiftUI

/// A tinted System-Settings glyph, a label, and a live value — the row idiom  uses.
/// Each row draws its own rounded card so the list reads as two calm blocks rather than a table.
struct QuickPanelRow: View {

    let symbol: String
    var tint: Color = .gray
    let title: String
    /// Drawn in full-strength text before `value`, separated by a dot: "Short · 1 min".
    var accent: String?
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(symbol: symbol, tint: tint, size: 22)
            Text(title)
                .font(TGType.row)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let accent {
                Text(accent)
                    .font(TGType.rowEmphasis)
                    .foregroundStyle(.primary)
                Text("·")
                    .font(TGType.row)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(TGType.row)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: TGType.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
