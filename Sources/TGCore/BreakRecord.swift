// TGCore — one break, stamped where it happened in the day.
//
// The counters (`breaksCompleted`, `breaksSkipped`, `breaksNatural`) say how many; this says
// *when*, which is what the rhythm timeline draws as ticks between the focus bars.

import Foundation

// MARK: - Outcome

public enum BreakOutcome: String, Codable, Sendable, Hashable, CaseIterable {
    /// TouchGrass put a break on screen and it ran to the end.
    case completed
    /// The user skipped it (or ended it early enough that it didn't count).
    case skipped
    /// The user was away long enough that the engine counted it as a break already taken.
    case natural
}

// MARK: - Record

public struct BreakRecord: Codable, Equatable, Sendable, Hashable {

    /// When the break started (for a skip: when it came due).
    public var at: Date
    public var kind: BreakKind
    public var outcome: BreakOutcome

    public init(at: Date, kind: BreakKind, outcome: BreakOutcome) {
        self.at = at
        self.kind = kind
        self.outcome = outcome
    }

    /// Ticks are drawn for rest that actually happened; a skip is drawn in clay instead.
    public var isRest: Bool { outcome != .skipped }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey { case at, kind, outcome }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = (try? c.decode(Date.self, forKey: .at)) ?? Date(timeIntervalSince1970: 0)
        kind = (try? c.decode(BreakKind.self, forKey: .kind)) ?? .short
        outcome = (try? c.decode(BreakOutcome.self, forKey: .outcome)) ?? .completed
    }
}
