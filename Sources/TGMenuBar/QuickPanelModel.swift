// TGMenuBar — which face of the quick panel is showing.
import Combine

/// The panel's navigation state, held outside the SwiftUI view so `QuickPanel` can open
/// straight onto a tab (the demo does this to snapshot Stats) and so the choice survives the
/// panel being closed and reopened.
@MainActor
final class QuickPanelModel: ObservableObject {
    @Published var tab: QuickPanelTab = .now
    /// Only meaningful on the Stats tab: false is today, true is the month grid.
    @Published var showingCalendar = false
}
