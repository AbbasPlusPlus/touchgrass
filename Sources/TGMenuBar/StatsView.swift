// TGMenuBar — the Stats tab: three facts about a day, in the ledger idiom.
import SwiftUI
import TGCore

/// Rest, rhythm, and where the time went — each behind its own uppercase eyebrow, separated by
/// stone hairlines, all left-aligned off the same margin as the Now tab.
///
/// No grade and no gauge. Every number here is a measurement the user can check against their
/// own memory of the day; nothing on this page tells them whether the day was good.
struct StatsView: View {

    @ObservedObject var stats: StatsStore
    @ObservedObject var settingsStore: SettingsStore
    /// How many days back the panel is showing. 0 is today; the ‹ › buttons walk it. Held by
    /// the panel's model so reopening the panel comes back to today.
    @Binding var daysBack: Int
    /// Injected so the demo can render a fixed day.
    var now: Date = Date()

    private var calendar: Calendar { .current }

    // MARK: - The day on show

    private var date: Date {
        calendar.date(byAdding: .day, value: -daysBack, to: now) ?? now
    }

    private var day: DayStats { stats.stats(for: date) }
    private var isToday: Bool { daysBack == 0 }

    /// Stepping further back is only offered while there is something recorded to step back to.
    private var canGoBack: Bool {
        guard let oldest = stats.oldestRecordedDayKey else { return false }
        return StatsStore.dayKey(for: date, calendar: calendar) > oldest
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                eyebrow("REST")
                Spacer(minLength: 8)
                dayNavigation
            }
            .padding(.top, 14)
            RestRatioView(day: day, settings: settingsStore.settings)
                .padding(.top, 10)

            hairline
                .padding(.top, 14)

            eyebrow("RHYTHM")
                .padding(.top, 14)
            RhythmTimelineView(
                day: day,
                settings: settingsStore.settings,
                date: date,
                now: isToday ? now : nil
            )
            .padding(.top, 10)

            // Hidden entirely when the user turned tracking off — an empty block would still be
            // a claim that we're watching.
            if settingsStore.settings.trackAppUsage {
                hairline
                    .padding(.top, 14)
                eyebrow("WHERE THE TIME WENT")
                    .padding(.top, 14)
                AppUsageCard(day: day)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Eyebrow

    /// The same uppercase label the Now tab opens with, so switching tabs doesn't switch
    /// typographic languages: `TODAY · REST`, `YESTERDAY · RHYTHM`, `MON 25 AUG · REST`.
    private func eyebrow(_ title: String) -> some View {
        let text = "\(dayLabel) \u{B7} \(title)"
        return Text(text)
            .font(TGType.eyebrow)
            .tracking(TGType.eyebrowTracking)
            .foregroundStyle(TGPalette.ink2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            // Caps and interpuncts are a typographic choice, not something to read out.
            .accessibilityLabel(text.capitalized.replacingOccurrences(of: " \u{B7} ", with: ", "))
    }

    private var dayLabel: String {
        switch daysBack {
        case 0: return "TODAY"
        case 1: return "YESTERDAY"
        default:
            // "MON 25 AUG" — the weekday and the date asked for separately, so the day/month
            // order follows the user's locale instead of being hard-coded.
            let weekday = date.formatted(.dateTime.weekday(.abbreviated))
            let dayMonth = date.formatted(.dateTime.day().month(.abbreviated))
            return "\(weekday) \(dayMonth)".uppercased()
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(TGPalette.stone)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    // MARK: - Day navigation

    /// ‹ › on the first eyebrow only: one control for the page, not one per block.
    private var dayNavigation: some View {
        HStack(spacing: 2) {
            IconButton(symbol: "chevron.left",
                       label: "Previous day",
                       size: 12,
                       diameter: 18,
                       isEnabled: canGoBack) {
                daysBack += 1
            }
            IconButton(symbol: "chevron.right",
                       label: "Next day",
                       size: 12,
                       diameter: 18,
                       isEnabled: daysBack > 0) {
                daysBack = max(0, daysBack - 1)
            }
        }
    }
}
