// TGMenuBar — "Launch at login" backed by SMAppService.
import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp`, including the well-known error 125 dance.
///
/// `register()` fails with `kSMErrorJobPlist` / 125 ("Service cannot load in requested session"
/// or a stale registration) when a *previous* copy of the bundle is still registered — typically
/// after a rebuild changes the code signature. Unregistering first clears the stale record.
@MainActor
public final class LoginItemManager: ObservableObject {

    /// Reflects `SMAppService.mainApp.status`, not our own bookkeeping — the user can turn
    /// this off in System Settings > General > Login Items and we must show that.
    @Published public private(set) var isEnabled: Bool = false
    /// Non-nil when the last register/unregister failed; surfaced inline on the General page.
    @Published public private(set) var lastError: String?

    private let service = SMAppService.mainApp

    public init() { refresh() }

    public func refresh() {
        isEnabled = service.status == .enabled
    }

    /// Returns the state actually achieved, so callers can snap a toggle back on failure.
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        lastError = nil
        do {
            if enabled {
                try registerWithRetry()
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            lastError = Self.describe(error)
        }
        refresh()
        return isEnabled
    }

    /// Human-readable status for the settings row.
    public var statusDescription: String {
        switch service.status {
        case .enabled: return "On"
        case .requiresApproval: return "Needs approval in System Settings"
        case .notFound: return "Unavailable — run the installed app"
        case .notRegistered: return "Off"
        @unknown default: return "Unknown"
        }
    }

    // MARK: - Private

    private func registerWithRetry() throws {
        do {
            try service.register()
        } catch let error as NSError where error.code == 125 {
            // Stale registration from an earlier build: clear it, then try once more.
            try? service.unregister()
            try service.register()
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.code == 125 {
            return "macOS refused the login item (125). Move TouchGrass to /Applications and try again."
        }
        return nsError.localizedDescription
    }
}
