// TGDetection — pid → owning application. Maps helper/XPC processes back to the app that owns them.
import AppKit
import Darwin
import Foundation

/// The app a pid belongs to, after helper→parent resolution.
public struct AppIdentity: Sendable, Hashable {
    public let pid: pid_t
    /// Bundle ID of the *owning* application ("com.raycast.macos"), not the helper.
    public let bundleID: String?
    /// Human-readable name for UI copy ("Raycast").
    public let name: String?
    /// Raw executable name of the pid itself ("Raycast Graphics and Media", "caffeinate").
    public let processName: String?
    /// How the identity was derived — surfaced in `debugSnapshot()`.
    public let source: Source

    public enum Source: String, Sendable, Hashable {
        case runningApplication      // NSRunningApplication(processIdentifier:) had a usable bundle
        case enclosingAppBundle      // walked the executable path up to the outermost .app
        case parentProcess           // walked the parent-pid chain to a running app
        case processNameOnly         // CLI tool, no bundle anywhere
        case unknown
    }

    public var isEmpty: Bool { bundleID == nil && name == nil }

    public var display: String {
        name ?? processName ?? "pid \(pid)"
    }
}

// MARK: -

/// Resolves pids to applications, with a short TTL cache (pids are reused, and helpers come and go).
@MainActor
public final class ProcessAppResolver {

    public static let shared = ProcessAppResolver()

    private struct Entry {
        let identity: AppIdentity
        let stamp: Date
    }

    private var cache: [pid_t: Entry] = [:]
    private let ttl: TimeInterval = 45
    /// How far up the parent chain to walk before giving up (launchd is pid 1).
    private let maxParentDepth = 5

    /// Processes that own their children only incidentally — walking past them invents an owner.
    static let opaqueParents: Set<String> = [
        "sh", "bash", "zsh", "dash", "fish", "csh", "tcsh", "ksh",
        "login", "launchd", "sudo", "env", "xargs", "tmux", "screen", "expect", "script",
    ]

    public init() {}

    public func invalidate() { cache.removeAll() }

    public func identity(for pid: pid_t) -> AppIdentity {
        if let e = cache[pid], Date().timeIntervalSince(e.stamp) < ttl { return e.identity }
        let identity = resolve(pid)
        cache[pid] = Entry(identity: identity, stamp: Date())
        return identity
    }

    // MARK: Resolution

    private func resolve(_ pid: pid_t) -> AppIdentity {
        let exePath = Self.executablePath(pid)
        let processName = exePath.map { ($0 as NSString).lastPathComponent }

        let direct = NSRunningApplication(processIdentifier: pid)

        // 1. A regular (Dock-visible) app that *is* this pid is already the answer.
        if let app = direct, app.activationPolicy == .regular, let bid = app.bundleIdentifier {
            return AppIdentity(pid: pid, bundleID: bid, name: app.localizedName ?? processName,
                               processName: processName, source: .runningApplication)
        }

        // 2. Helpers live inside their owner's bundle: /Applications/Slack.app/Contents/Frameworks/
        //    Slack Helper.app/Contents/MacOS/Slack Helper → the *outermost* .app is Slack.
        if let path = exePath, let (bid, name) = Self.enclosingAppBundle(path) {
            return AppIdentity(pid: pid, bundleID: bid, name: Self.preferredName(bundleID: bid) ?? name,
                               processName: processName, source: .enclosingAppBundle)
        }

        // 3. Otherwise follow the parent chain — this is what maps WebKit's GPU/Networking helpers
        //    (which live in a system framework, not the browser's bundle) back to the browser.
        //    The walk stops at a shell: `caffeinate` started from a terminal belongs to nobody, and
        //    blaming whichever app happens to host that terminal would be a lie.
        var parent = Self.parentPID(pid)
        var depth = 0
        while let p = parent, p > 1, depth < maxParentDepth {
            if let name = Self.executablePath(p).map({ ($0 as NSString).lastPathComponent.lowercased() }),
               Self.opaqueParents.contains(name) {
                break
            }
            if let app = NSRunningApplication(processIdentifier: p), let bid = app.bundleIdentifier,
               app.activationPolicy != .prohibited {
                return AppIdentity(pid: pid, bundleID: bid, name: app.localizedName,
                                   processName: processName, source: .parentProcess)
            }
            if let ppath = Self.executablePath(p), let (bid, name) = Self.enclosingAppBundle(ppath) {
                return AppIdentity(pid: pid, bundleID: bid, name: Self.preferredName(bundleID: bid) ?? name,
                                   processName: processName, source: .parentProcess)
            }
            parent = Self.parentPID(p)
            depth += 1
        }

        // 4. Agent/accessory app with a bundle but no window (menu-bar apps).
        if let app = direct, let bid = app.bundleIdentifier {
            return AppIdentity(pid: pid, bundleID: bid, name: app.localizedName ?? processName,
                               processName: processName, source: .runningApplication)
        }

        if let processName {
            return AppIdentity(pid: pid, bundleID: nil, name: processName,
                               processName: processName, source: .processNameOnly)
        }
        return AppIdentity(pid: pid, bundleID: nil, name: nil, processName: nil, source: .unknown)
    }

    /// Prefer the running app's localized name — Info.plist names are often the raw executable name.
    private static func preferredName(bundleID: String) -> String? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
    }

    // MARK: Low-level process queries

    /// `proc_pidpath` — works for any pid we're allowed to see; no entitlement, no TCC.
    public static func executablePath(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 2)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return nil }
        return String(cString: buf)
    }

    /// Parent pid via `sysctl(KERN_PROC_PID)`. `proc_pidinfo(PROC_PIDTBSDINFO)` is the alternative but
    /// needs a matching struct layout; sysctl is stable and needs no privileges.
    public static func parentPID(_ pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let rc = sysctl(&mib, 4, &info, &size, nil, 0)
        guard rc == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }

    /// First `.app` component of a path (outermost wins → Slack, not "Slack Helper").
    public static func enclosingAppBundle(_ executablePath: String) -> (bundleID: String, name: String)? {
        let comps = (executablePath as NSString).pathComponents
        guard let idx = comps.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let appPath = NSString.path(withComponents: Array(comps[0...idx]))
        guard let bundle = Bundle(path: appPath), let bid = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
        return (bid, name)
    }
}
