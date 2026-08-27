// TGUpdate — semantic-ish version parsing and ordering. Pure Swift, no I/O.
import Foundation

/// A dotted version number ("0.2.0", "v1.10.3", "2.0.0-beta.1", "1.2.3+deadbeef").
///
/// Ordering is semver-flavoured but forgiving, because the numbers come from an Info.plist a
/// human typed: missing components read as zero (`1.2` == `1.2.0`), a leading `v` is ignored,
/// build metadata after `+` is ignored, and any pre-release suffix sorts *below* the release
/// with the same numbers (`1.0.0-beta` < `1.0.0`).
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {

    // MARK: Storage

    /// Numeric components, at least one, trailing zeros preserved as written.
    public let numbers: [Int]
    /// Dot-separated pre-release identifiers; empty for a final release.
    public let prerelease: [String]

    // MARK: Init

    /// Returns `nil` when the string has no leading numeric component at all.
    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        // Build metadata is not part of the ordering.
        if let plus = text.firstIndex(of: "+") { text = String(text[text.startIndex..<plus]) }

        let core: String
        if let dash = text.firstIndex(of: "-") {
            core = String(text[text.startIndex..<dash])
            let tail = String(text[text.index(after: dash)...])
            prerelease = tail.isEmpty ? [] : tail.split(separator: ".").map(String.init)
        } else {
            core = text
            prerelease = []
        }

        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var parsed: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { break }
            parsed.append(value)
        }
        guard !parsed.isEmpty else { return nil }
        numbers = parsed
    }

    public init(numbers: [Int], prerelease: [String] = []) {
        self.numbers = numbers.isEmpty ? [0] : numbers
        self.prerelease = prerelease
    }

    // MARK: Comparable

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let width = max(lhs.numbers.count, rhs.numbers.count)
        for i in 0..<width {
            let a = i < lhs.numbers.count ? lhs.numbers[i] : 0
            let b = i < rhs.numbers.count ? rhs.numbers[i] : 0
            if a != b { return a < b }
        }
        return comparePrerelease(lhs.prerelease, rhs.prerelease) == .orderedAscending
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let width = max(lhs.numbers.count, rhs.numbers.count)
        for i in 0..<width {
            let a = i < lhs.numbers.count ? lhs.numbers[i] : 0
            let b = i < rhs.numbers.count ? rhs.numbers[i] : 0
            if a != b { return false }
        }
        return comparePrerelease(lhs.prerelease, rhs.prerelease) == .orderedSame
    }

    public func hash(into hasher: inout Hasher) {
        // Must agree with `==`, which ignores trailing zeros.
        var trimmed = numbers
        while trimmed.count > 1, trimmed.last == 0 { trimmed.removeLast() }
        hasher.combine(trimmed)
        hasher.combine(prerelease)
    }

    /// A release outranks any pre-release of the same numbers; otherwise identifiers are
    /// compared left to right, numerically when both sides are numeric.
    private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> ComparisonResult {
        if lhs.isEmpty && rhs.isEmpty { return .orderedSame }
        if lhs.isEmpty { return .orderedDescending }
        if rhs.isEmpty { return .orderedAscending }
        for i in 0..<max(lhs.count, rhs.count) {
            guard i < lhs.count else { return .orderedAscending }
            guard i < rhs.count else { return .orderedDescending }
            let a = lhs[i], b = rhs[i]
            if let na = Int(a), let nb = Int(b) {
                if na != nb { return na < nb ? .orderedAscending : .orderedDescending }
            } else if a != b {
                return a < b ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    // MARK: Description

    public var description: String {
        let core = numbers.map(String.init).joined(separator: ".")
        return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
    }
}
