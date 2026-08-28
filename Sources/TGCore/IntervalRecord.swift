// TGCore — a stretch of the day the engine spent paused.
//
// The rhythm timeline draws these hatched: a call, a video, a fullscreen app or a walk away is
// time we have deliberately stopped judging. It isn't screen time and it isn't rest, so it needs
// its own record rather than a hole in the session list.

import Foundation

// MARK: - Kind

/// Why a pause span happened, flattened from `PauseReason` to the handful of cases worth drawing.
///
/// A separate type from `PauseReason` on purpose: `PauseReason` carries app names and dates that
/// have no business being persisted for a year, and its cases can grow without invalidating a
/// stats.json written by an older build.
public enum PauseKind: String, Codable, Sendable, Hashable, CaseIterable {
    case meeting
    case video
    case fullscreen
    case deepFocus
    case idle
    case manual
    case other

    // MARK: Mapping

    public init(_ reason: PauseReason) {
        switch reason {
        case .meeting: self = .meeting
        case .video: self = .video
        case .fullscreenApp: self = .fullscreen
        case .deepFocusApp: self = .deepFocus
        case .idle: self = .idle
        case .manual: self = .manual
        case .focusMode, .screenLocked, .outsideOfficeHours: self = .other
        }
    }

    /// The reason worth naming when several are true at once, most specific first: being in a
    /// call explains a pause better than the fullscreen window the call is in.
    public static func primary(of reasons: Set<PauseReason>) -> PauseKind? {
        let kinds = Set(reasons.map(PauseKind.init))
        let order: [PauseKind] = [.meeting, .video, .deepFocus, .fullscreen, .manual, .idle, .other]
        return order.first { kinds.contains($0) }
    }

    /// For the timeline's tooltip and the legend.
    public var label: String {
        switch self {
        case .meeting: return "Call"
        case .video: return "Video"
        case .fullscreen: return "Fullscreen"
        case .deepFocus: return "Deep focus"
        case .idle: return "Away"
        case .manual: return "Paused"
        case .other: return "Paused"
        }
    }
}

// MARK: - Record

/// One paused span: when it began, how long it lasted, and why.
public struct IntervalRecord: Codable, Equatable, Sendable, Hashable {

    public var start: Date
    public var duration: TimeInterval
    public var kind: PauseKind

    public init(start: Date, duration: TimeInterval, kind: PauseKind) {
        self.start = start
        self.duration = max(0, duration)
        self.kind = kind
    }

    public var end: Date { start.addingTimeInterval(duration) }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey { case start, duration, kind }

    /// Lenient like every other record here: an unknown `kind` from a future build reads as
    /// `.other` rather than throwing away the day it was written in.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = (try? c.decode(Date.self, forKey: .start)) ?? Date(timeIntervalSince1970: 0)
        duration = max(0, (try? c.decode(TimeInterval.self, forKey: .duration)) ?? 0)
        kind = (try? c.decode(PauseKind.self, forKey: .kind)) ?? .other
    }
}
