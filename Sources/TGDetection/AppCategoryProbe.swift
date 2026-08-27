// TGDetection — reads an app's `LSApplicationCategoryType` out of its Info.plist.
//
// This is the "is it a game?" input for fullscreen auto-pause. It is plain file I/O on a bundle we
// were already handed by NSWorkspace — no permission, no private API — but it *is* disk I/O, so the
// answer is cached per bundle ID. A bundle's category never changes without the app being replaced,
// and a replaced app gets a fresh launch anyway, so the cache never needs invalidating in practice
// (`invalidate()` exists for tests and for the wake path).
import AppKit
import Foundation

@MainActor
public enum AppCategoryProbe {

    /// bundle ID → category. `""` memoises "this app declares none", so we don't re-open the plist.
    private static var cache: [String: String] = [:]

    // MARK: Queries

    /// `LSApplicationCategoryType` for a running app, or nil when it declares none / can't be read.
    public static func category(pid: pid_t, bundleID: String?) -> String? {
        let key = BundleMatch.normalize(bundleID)
        if let key, let cached = cache[key] { return cached.isEmpty ? nil : cached }

        guard let app = NSRunningApplication(processIdentifier: pid),
              let url = app.bundleURL else { return nil }
        let value = Bundle(url: url)?.infoDictionary?["LSApplicationCategoryType"] as? String

        if let key { cache[key] = value ?? "" }
        return value
    }

    ///  parity: fullscreen auto-pause is for *games*. Everything else the user must add to
    /// Deep Focus Apps explicitly.
    public static func isGame(pid: pid_t, bundleID: String?) -> Bool {
        KnownBundles.isGame(bundleID: bundleID, category: category(pid: pid, bundleID: bundleID))
    }

    // MARK: Cache

    public static func invalidate() { cache.removeAll() }
}
