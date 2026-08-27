// TGMenuBar — the settings window's SwiftUI root.
import SwiftUI
import TGCore

/// Sidebar on the left, a grouped `Form` on the right. Every page binds straight to
/// `SettingsStore`, which persists on change — there is no Save button and no Cancel.
struct SettingsView: View {

    @ObservedObject var store: SettingsStore
    @ObservedObject var loginItems: LoginItemManager
    @ObservedObject var selection: SettingsSelection

    let previewSound: (SoundStyle, String) -> Void
    let onShowOnboarding: () -> Void
    let onQuit: () -> Void

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection.section)
                .navigationSplitViewColumnWidth(min: 194, ideal: 210, max: 260)
        } detail: {
            VStack(spacing: 0) {
                SettingsPageHeader(section: selection.section, subtitle: selection.section.blurb)
                Rectangle().fill(TGPalette.stone).frame(height: 1)
                page
                    // Grouped forms paint their own window-coloured backdrop; hide it so the
                    // page sits on paper like everything else.
                    .scrollContentBackground(.hidden)
            }
            .frame(minWidth: 470)
            .background(TGPalette.paper)
        }
        .navigationSplitViewStyle(.balanced)
        // Matcha is the selection colour everywhere: sidebar rows, switches, steppers, focus.
        .tint(TGPalette.matcha)
        .foregroundStyle(TGPalette.ink)
    }

    @ViewBuilder
    private var page: some View {
        switch selection.section {
        case .screenBreaks:
            ScreenBreaksPage(store: store)
        case .smartPause:
            SmartPausePage(store: store)
        case .wellness:
            WellnessPage(store: store)
        case .alerts:
            AlertsPage(store: store)
        case .appearance:
            AppearancePage(store: store)
        case .sounds:
            SoundsPage(store: store, previewSound: previewSound)
        case .shortcuts:
            ShortcutsPage(store: store)
        case .general:
            GeneralPage(
                store: store,
                loginItems: loginItems,
                onShowOnboarding: onShowOnboarding,
                onQuit: onQuit
            )
        case .about:
            AboutPage()
        }
    }
}
