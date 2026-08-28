// TGOverlay — where the sprout is at a given moment in a nudge.
//
// One value type for the whole composition (stack, leaves, plant, droplet) and one function
// per motion that fills it in. Timings and angles are the approved mock's, converted from
// percentages of its 3.6 s cycle.

import Foundation

/// A single frame of the nudge. Defaults are the resting frame — what Reduce Motion shows.
struct SproutPose {

    // The stack (sprout + word pill together).
    var opacity: Double = 1
    /// Points of vertical offset; negative is up.
    var lift: Double = 0
    var scale: Double = 1

    // The leaves. `angle` is the *left* leaf's rotation; the right leaf mirrors it.
    var leafAngle: Double = 0
    var leafSquash: Double = 1
    var leafScale: Double = 1

    // The whole plant, about the foot of the stem.
    var lean: Double = 0
    var stretch: Double = 1

    // The droplet, in box units.
    var dropletY: Double = 0
    var dropletOpacity: Double = 0
    var dropletScaleX: Double = 1
    var dropletScaleY: Double = 1

    static let rest = SproutPose()
}

// MARK: - Motions

/// What the sprout does while the word sits still under it.
enum NudgeMotion {
    /// Both leaves fold shut and reopen, once.
    case blink
    /// The plant starts leaning and straightens up.
    case posture
    /// Straightens *and* grows a little taller.
    case stretch
    /// A droplet falls onto the leaf join, runs down the stem, and the leaves perk up after it.
    case water
    /// A gentle two-beat rustle — the fallback for any other custom reminder.
    case rustle

    /// How long one nudge lives, start of fade-in to end of fade-out.
    static let lifetime: TimeInterval = 3.6

    // MARK: Custom reminders

    /// Picks the motion a user-defined reminder should get from what it says it is.
    /// Anything we can't recognise rustles — never nothing.
    static func forCustom(title: String, symbol: String) -> NudgeMotion {
        let lowered = title.lowercased()
        if lowered.contains("water") || symbol == "drop.fill" { return .water }
        if lowered.contains("stretch") || symbol == "figure.cooldown" { return .stretch }
        return .rustle
    }

    /// The reminder's title as the one word on the pill: trimmed, full-stopped.
    static func word(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return "" }
        return ".!?…".contains(last) ? trimmed : trimmed + "."
    }

    // MARK: Sampling

    /// The frame at `t`, a 0…1 position through the nudge's life.
    func pose(at t: Double) -> SproutPose {
        var pose = SproutPose()
        pose.opacity = Self.stackOpacity(t)
        pose.lift = Self.stackLift(t)
        pose.scale = Self.stackScale(t)

        switch self {
        case .blink:
            pose.leafAngle = Self.fold(t)
            pose.leafSquash = Self.foldSquash(t)
        case .posture:
            pose.lean = Self.straighten(t)
        case .stretch:
            pose.lean = Self.straighten(t)
            pose.stretch = Self.grow(t)
        case .water:
            pose.leafAngle = Self.perk(t)
            pose.leafScale = Self.perkScale(t)
            pose.dropletY = Self.dropFall(t)
            pose.dropletOpacity = Self.dropOpacity(t)
            pose.dropletScaleX = Self.dropWide(t)
            pose.dropletScaleY = Self.dropTall(t)
        case .rustle:
            pose.leafAngle = Self.sway(t)
        }
        return pose
    }

    // MARK: - Tracks
    // Mock: `@keyframes chip` — the stack fades and rises in, holds, and leaves the same way.

    private static let stackOpacity = NudgeTrack([(0, 0), (0.14, 1), (0.78, 1), (1, 0)])
    private static let stackLift = NudgeTrack([(0, 10), (0.14, 0), (0.78, 0), (1, -8)])
    private static let stackScale = NudgeTrack([(0, 0.96), (0.14, 1), (0.78, 1), (1, 0.98)])

    // `foldL` / `foldR` — shut at 48–56%, open either side of it.
    private static let fold = NudgeTrack([(0, 0), (0.38, 0), (0.48, 40), (0.56, 40), (0.66, 0)])
    private static let foldSquash = NudgeTrack([(0, 1), (0.38, 1), (0.48, 0.3), (0.56, 0.3), (0.66, 1)])

    // `straighten` — leaning at rest, upright by 56%, and it stays upright (the mock loops back;
    // a one-shot nudge shouldn't slump again on its way out).
    private static let straighten = NudgeTrack([(0, 16), (0.22, 16), (0.56, 0)])
    private static let grow = NudgeTrack([(0, 1), (0.22, 1), (0.56, 1.08)])

    // `stemdrop` — falls onto the join, squashes, runs down the stem, fades at the foot.
    private static let dropFall = NudgeTrack([(0, -30), (0.28, -30), (0.44, 0), (0.46, 0),
                                              (0.80, 32), (0.88, 36)], ease: .easeIn)
    private static let dropOpacity = NudgeTrack([(0, 0), (0.22, 0), (0.28, 1), (0.80, 1), (0.88, 0)])
    private static let dropWide = NudgeTrack([(0, 1), (0.44, 1), (0.46, 1.15), (0.80, 0.9), (0.88, 0.3)])
    private static let dropTall = NudgeTrack([(0, 1), (0.44, 1), (0.46, 0.85), (0.80, 0.9), (0.88, 0.3)])

    // `perkL` / `perkR` — drooping until the water reaches them, then lifted and a touch larger.
    private static let perk = NudgeTrack([(0, 10), (0.50, 10), (0.64, -6)])
    private static let perkScale = NudgeTrack([(0, 1), (0.50, 1), (0.64, 1.06)])

    // Two beats of ±6°, for a reminder we have no better idea about.
    private static let sway = NudgeTrack([(0, 0), (0.20, 0), (0.32, 6), (0.44, -6),
                                            (0.56, 6), (0.68, 0)])
}
