// TGOverlay — the wellness nudge: a seedling floating above one serif word.
//
// No chip around the plant, no caption, no controls. The sprout carries the meaning (leaves
// fold for blink, the stem straightens for posture, a droplet runs down it for water) and the
// word underneath removes the guesswork. Both arrive and leave together; only the sprout moves.

import SwiftUI

struct SproutNudgeView: View {

    /// The frame the controller sizes its panel to. Generous: the pill grows with the word and
    /// the panel is click-through, so spare room costs nothing.
    static let size = CGSize(width: 400, height: 250)

    let motion: NudgeMotion
    /// One or two words, ending in a full stop: "Blink." · "Sit up." · "Water."
    let word: String
    var lifetime: TimeInterval = NudgeMotion.lifetime

    /// The plant, in points. The word pill sizes itself.
    private static let sproutSize: CGFloat = 104
    private static let gap: CGFloat = 18
    /// Reduce Motion still cross-fades — that is the recommended substitute for movement,
    /// not something to remove as well.
    private static let fadeDuration: Double = 0.35

    @State private var started: Date?
    @State private var visible = false

    // MARK: - Body

    var body: some View {
        Group {
            if OverlayMotion.reduceMotion {
                stack(.rest).opacity(visible ? 1 : 0)
            } else {
                TimelineView(.animation) { context in
                    stack(motion.pose(at: progress(at: context.date)))
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityElement()
        .accessibilityLabel(word)
        .onAppear(perform: begin)
    }

    // MARK: - Timing

    private func begin() {
        guard OverlayMotion.reduceMotion else {
            started = Date()
            return
        }
        withAnimation(.easeInOut(duration: Self.fadeDuration)) { visible = true }
        Task { @MainActor in
            let hold = max(0, lifetime - Self.fadeDuration)
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            withAnimation(.easeInOut(duration: Self.fadeDuration)) { visible = false }
        }
    }

    /// Wall-clock position through the nudge, 0…1. Never a frame count: a dropped frame should
    /// cost smoothness, not timing.
    private func progress(at date: Date) -> Double {
        guard let started, lifetime > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(started) / lifetime))
    }

    // MARK: - Composition

    private func stack(_ pose: SproutPose) -> some View {
        VStack(spacing: Self.gap) {
            sprout(pose)
            pill
        }
        .scaleEffect(pose.scale)
        .offset(y: pose.lift)
        .opacity(pose.opacity)
    }

    private var pill: some View {
        Text(word)
            .font(OverlayType.nudgeWord)
            .foregroundStyle(OverlayPalette.ink)
            .fixedSize()
            .padding(.horizontal, 26)
            .padding(.vertical, 12)
            .glassSurface(Capsule(), shadowRadius: 22, shadowY: 8)
    }

    // MARK: - The plant

    private func sprout(_ pose: SproutPose) -> some View {
        let unit = SproutMark.unit(for: Self.sproutSize)
        return ZStack {
            // Behind the stem, so it reads as running *down* the plant.
            SproutShape(part: .droplet)
                .fill(SproutMark.droplet)
                .scaleEffect(x: pose.dropletScaleX, y: pose.dropletScaleY,
                             anchor: SproutMark.anchor(SproutMark.dropletCentre))
                .offset(y: pose.dropletY * unit)
                .opacity(pose.dropletOpacity)

            SproutShape(part: .stem)
                .stroke(SproutMark.stem,
                        style: StrokeStyle(lineWidth: SproutMark.stemWidth * unit, lineCap: .round))

            leaf(.leftLeaf, colour: SproutMark.leafLeft, angle: pose.leafAngle, pose: pose)
            leaf(.rightLeaf, colour: SproutMark.leafRight, angle: -pose.leafAngle, pose: pose)
        }
        .frame(width: Self.sproutSize, height: Self.sproutSize)
        .rotationEffect(.degrees(pose.lean), anchor: SproutMark.anchor(SproutMark.base))
        .scaleEffect(x: 1, y: pose.stretch, anchor: SproutMark.anchor(SproutMark.base))
        // The mock's drop-shadow: the plant floats, so it needs a ground of its own.
        .shadow(color: .black.opacity(0.35), radius: 7, y: 8)
    }

    /// A leaf, scaled then rotated about the join — the same order the mock's
    /// `rotate(…) scaleY(…)` composes in.
    private func leaf(_ part: SproutShape.Part, colour: Color,
                      angle: Double, pose: SproutPose) -> some View {
        SproutShape(part: part)
            .fill(colour)
            .scaleEffect(x: pose.leafScale, y: pose.leafScale * pose.leafSquash,
                         anchor: SproutMark.anchor(SproutMark.join))
            .rotationEffect(.degrees(angle), anchor: SproutMark.anchor(SproutMark.join))
    }
}
