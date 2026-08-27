// TGMenuBar — the currently-open settings page, shared between SwiftUI and the NSWindow.
import Combine

/// The window needs to know which page is showing (to title itself), and the window controller
/// needs to be able to jump to a page. A tiny observable object bridges both directions.
@MainActor
final class SettingsSelection: ObservableObject {
    @Published var section: SettingsSection = .screenBreaks
}
