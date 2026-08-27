// TGMenuBar — Settings ▸ Screen Breaks ▸ Office hours. When TouchGrass is on the clock.
import SwiftUI
import TGCore

/// The working-hours window: a switch, two time fields, seven day chips and a plain-English
/// summary of what that adds up to.
///
/// `Settings` stores minutes from midnight, which is what the engine wants; `DatePicker` wants a
/// `Date`, so the two bindings below convert against today's midnight. An end earlier than the
/// start is legal and means "past midnight" — the summary says so rather than treating it as an error.
struct OfficeHoursSection: View {

    @ObservedObject var store: SettingsStore

    private let calendar = Calendar.current

    var body: some View {
        Section {
            Toggle("Only remind me during office hours", isOn: $store.settings.officeHoursEnabled)
            if store.settings.officeHoursEnabled {
                DatePicker(
                    "Start",
                    selection: minuteBinding(\.officeHoursStart),
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "End",
                    selection: minuteBinding(\.officeHoursEnd),
                    displayedComponents: .hourAndMinute
                )
                LabeledContent("Days") {
                    WeekdayChipRow(days: $store.settings.officeDays)
                }
                LabeledContent("Schedule", value: summary)
            }
        } header: {
            Text("Office hours")
        } footer: {
            Text(footnote)
        }
    }

    // MARK: - Bindings

    /// Minutes-from-midnight ⇄ a `Date` on today's date, which is all `DatePicker` needs.
    private func minuteBinding(_ keyPath: WritableKeyPath<TGCore.Settings, Int>) -> Binding<Date> {
        Binding(
            get: { date(fromMinutes: store.settings[keyPath: keyPath]) },
            set: { store.settings[keyPath: keyPath] = minutes(from: $0) }
        )
    }

    private func date(fromMinutes minute: Int) -> Date {
        let wrapped = OfficeHours.wrap(minute)
        let midnight = calendar.startOfDay(for: Date())
        return midnight.addingTimeInterval(TimeInterval(wrapped * 60))
    }

    private func minutes(from date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    // MARK: - Copy

    /// "09:00 to 18:00 on weekdays" — in the user's own time format.
    private var summary: String {
        let start = timeFormatter.string(from: date(fromMinutes: store.settings.officeHoursStart))
        let end = timeFormatter.string(from: date(fromMinutes: store.settings.officeHoursEnd))
        return "\(start) to \(end) \(daysPhrase)"
    }

    private var footnote: String {
        guard store.settings.officeHoursEnabled else {
            return "Off: breaks are counted around the clock, every day."
        }
        if store.settings.officeDays.isEmpty {
            return "No days selected — breaks stay paused until you pick at least one."
        }
        if isOvernight {
            return "The window runs past midnight, so a shift that starts on one of these days carries on into the next morning. Outside it the menu bar reads \"Off hours\" and the timer sits still."
        }
        return "Outside these hours the menu bar reads \"Off hours\" and the timer sits still. Walking back in starts a fresh interval."
    }

    private var isOvernight: Bool {
        OfficeHours.wrap(store.settings.officeHoursEnd) <= OfficeHours.wrap(store.settings.officeHoursStart)
    }

    private var daysPhrase: String {
        let days = store.settings.officeDays
        if days.isEmpty { return "on no days" }
        if days == Set(1...7) { return "every day" }
        if days == [2, 3, 4, 5, 6] { return "on weekdays" }
        if days == [1, 7] { return "on weekends" }
        let symbols = calendar.shortWeekdaySymbols
        let ordered = (0..<7)
            .map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
            .filter { days.contains($0) }
            .compactMap { $0 <= symbols.count ? symbols[$0 - 1] : nil }
        return "on " + ordered.joined(separator: ", ")
    }

    /// Locale-aware "9:00 AM" / "09:00" — never a hard-coded 24-hour clock.
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter
    }
}
