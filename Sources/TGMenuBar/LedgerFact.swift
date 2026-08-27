// TGMenuBar — one entry of the Now tab's facts column.
import SwiftUI

/// A quiet label with its value under it: "Focused" / "**8 mins**".
///
/// No card, no icon, no hover: these are facts on a page, not controls. The hierarchy is
/// carried entirely by size and colour, which is what lets the column sit beside the action
/// pills without competing with them.
struct LedgerFact: View {

    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(TGType.factLabel)
                .foregroundStyle(TGPalette.ink2)
            Text(value)
                .font(TGType.factValue)
                .foregroundStyle(TGPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
