// TGOverlay — CSS-style keyframes for the wellness nudge.
//
// The nudge was designed as a CSS animation: a fixed-length cycle with stops at percentages.
// Rather than translate that into a chain of `withAnimation` sleeps (which drift, and lose the
// shape of the original), each channel keeps its stops and is sampled against one wall-clock
// position through the cycle.

import Foundation

/// The easing between two stops. Named after the CSS timing functions they stand in for.
enum NudgeEase {
    case linear
    /// Accelerating — a falling droplet.
    case easeIn
    case easeOut
    /// The default, and what everything in the mock uses unless it says otherwise.
    case easeInOut

    func apply(_ x: Double) -> Double {
        let x = min(1, max(0, x))
        switch self {
        case .linear: return x
        case .easeIn: return x * x
        case .easeOut: return 1 - (1 - x) * (1 - x)
        case .easeInOut: return 0.5 - cos(.pi * x) / 2
        }
    }
}

/// One animated channel: values pinned to positions in the 0…1 cycle, eased between.
///
/// Positions must be ascending. Before the first stop and after the last, the track holds —
/// which is how a one-shot nudge keeps the pose the loop in the mock would have unwound.
struct NudgeTrack {

    private let stops: [(at: Double, value: Double)]
    private let ease: NudgeEase

    init(_ stops: [(Double, Double)], ease: NudgeEase = .easeInOut) {
        self.stops = stops.map { (at: $0.0, value: $0.1) }
        self.ease = ease
    }

    func callAsFunction(_ t: Double) -> Double {
        guard let first = stops.first, let last = stops.last else { return 0 }
        if t <= first.at { return first.value }
        for (a, b) in zip(stops, stops.dropFirst()) where t <= b.at {
            let span = b.at - a.at
            guard span > 0 else { return b.value }
            return a.value + (b.value - a.value) * ease.apply((t - a.at) / span)
        }
        return last.value
    }
}
