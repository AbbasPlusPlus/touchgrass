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
            eyebrow
            statGauge(stat: day.stats, hasData: day.hasData)
                .padding(.top, 4)
                .padding(.bottom, 2)
            StatsInsightRow(day: day, interval: settingsStore.settings.shortBreakInterval)
            StatsExplainer()
            BreakStatsCard(day: day)
            // Hidden entirely when the user turned tracking off — an empty card would still be
            // a claim that we're watching.
            if settingsStore.settings.trackAppUsage {
                AppUsageCard(day: day)
            }
        }
        .padding(.top, 12)
    }

    /// The same uppercase label the Now tab opens with, so switching tabs doesn't switch
    /// typographic languages. Left-aligned for the same reason.
    private var eyebrow: some View {
        Text("TODAY \u{B7} stats")
            .font(TGType.eyebrow)
            .tracking(TGType.eyebrowTracking)
            .foregroundStyle(TGPalette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}
