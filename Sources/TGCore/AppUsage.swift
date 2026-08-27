// TGCore — how long each app was in front today.
//
// The frontmost application is public information (`NSWorkspace`), so this needs no permission
// of any kind: no Screen Recording, no Accessibility, no window titles, no URLs. One name and
// one running total per bundle ID, kept alongside the day's other counters and never leaving
// this Mac.

import Foundation

/// One app's share of a day's screen time.
///
/// The name is stored as well as the bundle ID so a day whose app has since been deleted still
/// renders as "Sketch" rather than as `com.bohemiancoding.sketch3`.
public struct AppUsage: Codable, Equatable, Sendable, Hashable {

    /// Localized application name at the time it was recorded.
    public var name: String
    /// Seconds this app spent frontmost while screen time was accruing.
    public var seconds: TimeInterval

    public init(name: String, seconds: TimeInterval = 0) {
        self.name = name
        self.seconds = max(0, seconds)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case name, seconds }

    /// Lenient, for the same reason `DayStats` is: a record written by a future build must not
    /// be able to throw away the file it lives in.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        seconds = max(0, (try? container.decode(TimeInterval.self, forKey: .seconds)) ?? 0)
    }
}

// MARK: - Ranked

/// An `AppUsage` with its key, ordered for display. `Identifiable` so a SwiftUI list can be
/// built straight from `DayStats.rankedAppUsage(limit:)`.
public struct RankedAppUsage: Identifiable, Equatable, Sendable, Hashable {
    public let bundleID: String
    public let name: String
    public let seconds: TimeInterval

    public var id: String { bundleID }

    public init(bundleID: String, name: String, seconds: TimeInterval) {
        self.bundleID = bundleID
        self.name = name
        self.seconds = seconds
    }
}

// MARK: - Day bookkeeping

extension DayStats {

    /// A day spent flicking through sixty applications is already more detail than the card can
    /// show; the cap stops a pathological day (or a scripted one) growing stats.json without
    /// bound. The *smallest* entries are the ones evicted — the card only ever draws the top of
    /// the list, and total screen time is counted separately, so nothing displayed is falsified.
    public static let maxTrackedApps = 60

    /// Credits `seconds` of frontmost time to `bundleID`.
    public mutating func addAppUsage(bundleID: String, name: String, seconds: TimeInterval) {
        guard seconds > 0, !bundleID.isEmpty else { return }
        var entry = appUsage[bundleID] ?? AppUsage(name: name.isEmpty ? bundleID : name)
        entry.seconds += seconds
        // An app that was renamed (or first seen through a helper) gets its better name.
        if !name.isEmpty { entry.name = name }
        appUsage[bundleID] = entry
        trimAppUsage()
    }

    /// The day's apps, longest first. Ties break on name so the order can't shuffle between
    /// two renders of the same data.
    public func rankedAppUsage(limit: Int? = nil) -> [RankedAppUsage] {
        let ranked = appUsage
            .map { RankedAppUsage(bundleID: $0.key, name: $0.value.name, seconds: $0.value.seconds) }
            .sorted {
                if $0.seconds != $1.seconds { return $0.seconds > $1.seconds }
                if $0.name != $1.name { return $0.name < $1.name }
                return $0.bundleID < $1.bundleID
            }
        guard let limit, limit >= 0, ranked.count > limit else { return ranked }
        return Array(ranked.prefix(limit))
    }

    /// Total seconds attributed to apps. Always ≤ `totalScreenTime`: seconds spent with no
    /// identifiable app in front (or with TouchGrass itself) are counted as screen time but
    /// belong to nobody.
    public var attributedAppTime: TimeInterval {
        appUsage.values.reduce(0) { $0 + $1.seconds }
    }

    // MARK: Private

    private mutating func trimAppUsage() {
        while appUsage.count > Self.maxTrackedApps,
              let smallest = appUsage.min(by: { lhs, rhs in
                  lhs.value.seconds != rhs.value.seconds
                      ? lhs.value.seconds < rhs.value.seconds
                      : lhs.key > rhs.key
              })?.key {
            appUsage.removeValue(forKey: smallest)
        }
    }
}
