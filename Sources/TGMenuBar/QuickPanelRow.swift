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
        HStack(spacing: 9) {
            SettingsIcon(symbol: symbol, tint: tint, size: 19)
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let accent {
                Text(accent)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                Text("·")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
