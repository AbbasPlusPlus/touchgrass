// TGMenuBar — the two faces of the quick panel.
import SwiftUI

/// "Now" is the countdown and the buttons; "Stats" is today's stats and the month.
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

    var body: some View {
        HStack(spacing: 2) {
            ForEach(QuickPanelTab.allCases, id: \.self) { item in
                Button { tab = item } label: {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 15)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(tab == item ? 0.16 : 0))
                        )
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(2)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}
