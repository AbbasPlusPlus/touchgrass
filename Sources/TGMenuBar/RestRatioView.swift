// TGMenuBar — how much of the day was rest, as one number and one ring.
import SwiftUI
import TGCore

/// Minutes rested per hour on screen, drawn as a breath: a matcha ring filling toward a whole
/// one at 1.0, which is what keeping the 20-20-20 rhythm comes to.
///
/// Deliberately not a grade. The ring never overfills, there is no red end and no green end, and
/// the only reference on screen is stated as a fact ("20-20-20 is about 1.0") rather than as a
/// target the user is failing.
struct RestRatioView: View {

    let day: DayStats
    let settings: TGCore.Settings

    // MARK: - Metrics

    private static let ringSize: CGFloat = 78
    private static let ringWidth: CGFloat = 6
    private static let leafSize: CGFloat = 20

    private var ratio: RestRatio { RestRatio.compute(for: day, settings: settings) }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ring
            numbers
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Ring

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(TGPalette.ink.opacity(0.12), lineWidth: Self.ringWidth)
            Circle()
                .trim(from: 0, to: max(0.001, ratio.progress))
                .stroke(TGPalette.matcha,
                        style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                // Start the fill at the top, the way a dial is read.
                .rotationEffect(.degrees(-90))
                .opacity(ratio.minutesPerHour == nil ? 0 : 1)
            Text("\u{1F33F}")
                .font(.system(size: Self.leafSize))
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
        .accessibilityHidden(true)
    }

    // MARK: - Numbers

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(headline)
                    .font(TGType.statNumber)
                    .foregroundStyle(TGPalette.ink)
                Text("min / hr")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(TGPalette.ink2)
            }
            // Fraunces carries a deep descender no digit uses, so the line box runs well past
            // the ink; trim it back or the caption floats away from the number.
            .padding(.bottom, -2)
            Text(caption)
                .font(TGType.caption)
                .foregroundStyle(TGPalette.ink2)
                .padding(.top, 6)
            Text("20-20-20 is about 1.0")
                .font(TGType.caption)
                .foregroundStyle(TGPalette.ink2.opacity(0.75))
                .padding(.top, 2)
        }
    }

    /// One decimal: the difference between 1.4 and 1.42 is noise, and a second digit invites
    /// the user to read a measurement into a rule of thumb.
    private var headline: String {
        guard let value = ratio.minutesPerHour else { return "\u{2014}" }
        return String(format: "%.1f", value)
    }

    private var caption: String {
        ratio.minutesPerHour == nil
            ? "not enough screen time yet to say"
            : "rested for every hour on screen"
    }

    private var accessibilityLabel: String {
        guard let value = ratio.minutesPerHour else {
            return "Rest: not enough screen time yet to say"
        }
        return String(format: "Rest: %.1f minutes rested for every hour on screen. "
                      + "Keeping the 20-20-20 rhythm is about 1.0.", value)
    }
}
