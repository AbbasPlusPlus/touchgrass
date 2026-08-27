// TGUpdate — what the UI shows.
import Foundation

/// The updater's whole observable surface. `readyToInstall` means the new build is already
/// downloaded, checksum-verified and unpacked next door — all that's left is the swap.
public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(Release)
    /// 0…1, or `nil` while the server hasn't told us the content length yet.
    case downloading(Double)
    case readyToInstall(Release)
    case error(String)

    public var isBusy: Bool {
        switch self {
        case .checking, .downloading: return true
        default: return false
        }
    }

    /// The release this state is about, when there is one.
    public var release: Release? {
        switch self {
        case .available(let r), .readyToInstall(let r): return r
        default: return nil
        }
    }
}
