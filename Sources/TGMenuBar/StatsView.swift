// TGMenuBar — the Stats tab: today's stats and what drove it.
import SwiftUI
import TGCore

/// One number, one sentence explaining it, the rules behind it, and the three counts it's made
/// of. Deliberately the same shape as the Now tab: a headline you read in a second, with the
/// detail underneath for the times you want it.
struct StatsView: View {

    @ObservedObject var stats: StatsStore
    @ObservedObject var settingsStore: SettingsStore
    /// Injected so the demo can render a fixed day.
    var now: Date = Date()

    private var day: DayStats { stats.stats(for: now) }

    var body: some View {
        VStack(spacing: 10) {
            chip
            statGauge(stat: day.stats, hasData: day.hasData)
                .padding(.top, 4)
                .padding(.bottom, 2)
            StatsInsightRow(day: day, interval: settingsStore.settings.shortBreakInterval)
            StatsExplainer()
            BreakStatsCard(day: day)
        }
        .padding(.top, 12)
    }

    private var chip: some View {
        Text("Today's stats")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.vertical, 5)
            .padding(.horizontal, 16)
            .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.09)))
            .accessibilityAddTraits(.isHeader)
    }
}
