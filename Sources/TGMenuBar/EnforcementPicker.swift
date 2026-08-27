// TGMenuBar — the three-up enforcement chooser on the Screen Breaks page.
import SwiftUI
import TGCore

/// Casual / Balanced / Hardcore, side by side.
struct EnforcementPicker: View {
    @Binding var enforcement: Enforcement

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Enforcement.allCases, id: \.self) { mode in
                EnforcementCard(
                    enforcement: mode,
                    isSelected: enforcement == mode,
                    action: { enforcement = mode }
                )
            }
        }
        .padding(.vertical, 2)
    }
}
