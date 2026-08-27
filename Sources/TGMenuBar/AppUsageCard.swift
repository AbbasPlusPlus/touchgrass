// TGMenuBar — where today's screen time actually went.
import AppKit
import SwiftUI
import TGCore

/// An inset card under Break Stats: the five apps you spent the most time in front of today,
/// each as icon · name · a thin proportional bar · a duration.
///
/// The bar is relative to the *day's own* leader rather than to any absolute scale — the
/// question this card answers is "what took the day", not "how many hours is a lot", which is
/// what the stat above is for. Collapsible, because the Stats tab has a height cap and a user
/// who doesn't care about the breakdown shouldn't have to scroll past it forever.
struct AppUsageCard: View {

    let day: DayStats

    /// UI state, not a preference worth versioning into settings.json — same reasoning as the
    /// stats explainer next to it.
    @AppStorage("stats.appsExpanded") private var expanded = true

    // MARK: - Metrics

    private static let topCount = 5
    private static let iconSize: CGFloat = 18
    private static let barWidth: CGFloat = 48
    private static let barHeight: CGFloat = 3.5
    private static let durationWidth: CGFloat = 52

    private var ranked: [RankedAppUsage] { day.rankedAppUsage() }
    private var top: [RankedAppUsage] { Array(ranked.prefix(Self.topCount)) }
    private var overflow: Int { max(0, ranked.count - Self.topCount) }
    /// The longest app of the day sets the full bar; everything else is drawn against it.
    private var longest: TimeInterval { max(1, top.first?.seconds ?? 1) }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded {
                Rectangle()
                    .fill(TGPalette.stone)
                    .frame(height: 1)
                    .padding(.top, 9)
                if top.isEmpty {
                    emptyState
                } else {
                    ForEach(top) { app in row(app) }
                    if overflow > 0 { moreLine }
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TGPalette.rowFill)
        )
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 9) {
            SettingsIcon(symbol: "square.grid.2x2.fill", tint: TGPalette.moss, size: 19)
            Text("Apps today")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(TGPalette.ink)
            Spacer(minLength: 8)
            Button { expanded.toggle() } label: {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TGPalette.ink2)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Hide apps" : "Show apps")
        }
        // Same as the explainer: the whole header brings the card back, rather than a hunt for
        // a 16-point chevron.
        .contentShape(Rectangle())
        .onTapGesture { if !expanded { expanded = true } }
    }

    private func row(_ app: RankedAppUsage) -> some View {
        HStack(spacing: 9) {
            icon(for: app)
            Text(app.name)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(TGPalette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            bar(fraction: app.seconds / longest)
            Text(TGFormat.compactElapsed(app.seconds))
                .font(.system(size: 12.5, design: .rounded))
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

    /// A hairline track with a matcha fill — proportion at a glance, without turning the card
    /// into a chart.
    private func bar(fraction: Double) -> some View {
        let clamped = min(1, max(0.04, fraction))
        return ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(TGPalette.stone)
            Capsule(style: .continuous)
                .fill(TGPalette.matcha)
                .frame(width: Self.barWidth * clamped)
        }
        .frame(width: Self.barWidth, height: Self.barHeight)
        .accessibilityHidden(true)
    }

    private var moreLine: some View {
        Text("+\(overflow) more")
            .font(TGType.footnote)
            .foregroundStyle(TGPalette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 27)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    private var emptyState: some View {
        Text("Apps show up here as you work.")
            .font(.system(size: 11.5))
            .foregroundStyle(TGPalette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 28)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}
