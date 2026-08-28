// TGMenuBar — where today's screen time actually went.
import AppKit
import SwiftUI
import TGCore

/// The last block of the Stats tab: the five apps you spent the most time in front of that day,
/// each as icon · name · a thin proportional bar · a duration.
///
/// The bar is relative to the *day's own* leader rather than to any absolute scale — the question
/// this answers is "what took the day", not "how many hours is a lot". No chrome of its own: the
/// eyebrow above it belongs to the page, like the two blocks before it.
struct AppUsageCard: View {

    let day: DayStats

    // MARK: - Metrics

    private static let topCount = 5
    private static let iconSize: CGFloat = 18
    private static let barHeight: CGFloat = 5
    private static let durationWidth: CGFloat = 52

    private var ranked: [RankedAppUsage] { day.rankedAppUsage() }
    private var top: [RankedAppUsage] { Array(ranked.prefix(Self.topCount)) }
    private var overflow: Int { max(0, ranked.count - Self.topCount) }
    /// The longest app of the day sets the full bar; everything else is drawn against it.
    private var longest: TimeInterval { max(1, top.first?.seconds ?? 1) }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if top.isEmpty {
                emptyState
            } else {
                ForEach(top) { app in row(app) }
            }
            footnote
        }
    }

    // MARK: - Pieces

    private func row(_ app: RankedAppUsage) -> some View {
        HStack(spacing: 9) {
            icon(for: app)
            Text(app.name)
                .font(.system(size: 13.5, design: .rounded))
                .foregroundStyle(TGPalette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            bar(fraction: app.seconds / longest)
            Text(TGFormat.compactElapsed(app.seconds))
                .font(.system(size: 13.5, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(TGPalette.ink2)
                .frame(width: Self.durationWidth, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(app.name), \(TGFormat.elapsed(app.seconds))")
    }

    @ViewBuilder
    private func icon(for app: RankedAppUsage) -> some View {
        if let image = AppIconCache.icon(for: app.bundleID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .accessibilityHidden(true)
        } else {
            // Uninstalled since, or an app Launch Services can't place. A stand-in keeps the
            // rows on one grid rather than letting the names jump left.
            RoundedRectangle(cornerRadius: Self.iconSize * 0.24, style: .continuous)
                .fill(TGPalette.stone)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .overlay(
                    Image(systemName: "app.dashed")
                        .font(.system(size: Self.iconSize * 0.5, weight: .medium))
                        .foregroundStyle(TGPalette.ink2)
                )
                .accessibilityHidden(true)
        }
    }

    /// A hairline track with a matcha fill, taking whatever width the names and durations leave
    /// — proportion at a glance, without turning the list into a chart.
    private func bar(fraction: Double) -> some View {
        let clamped = min(1, max(0.04, fraction))
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(TGPalette.stone)
                Capsule(style: .continuous)
                    .fill(TGPalette.matcha)
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: Self.barHeight)
        .frame(maxWidth: .infinity)
        .padding(.leading, 6)
        .accessibilityHidden(true)
    }

    /// Says what was left out and, in the same breath, what this list is and isn't: the
    /// frontmost app, counted on this Mac, going nowhere.
    private var footnote: some View {
        Text(footnoteText)
            .font(.system(size: 12.5, design: .rounded))
            .foregroundStyle(TGPalette.ink2.opacity(0.75))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    private var footnoteText: String {
        let provenance = "frontmost app only, stays on this Mac"
        return overflow > 0 ? "+\(overflow) more \u{B7} \(provenance)" : provenance
    }

    private var emptyState: some View {
        Text("Apps show up here as you work.")
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(TGPalette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}
