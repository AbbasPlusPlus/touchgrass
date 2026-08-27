// TGCore — the office-hours window. Pure minutes-of-day arithmetic; no engine state, no AppKit.
//
// A window is a start minute, an end minute and a set of weekdays. The weekdays name the days the
// window *starts* on, so an overnight window (07:00 → 00:30 on Fridays) still covers the small
// hours of Saturday morning even though Saturday isn't a working day.

import Foundation

public enum OfficeHours {

    public static let minutesPerDay = 24 * 60

    // MARK: - Window arithmetic

    /// Length of the window in minutes. `end == start` is read as "all day" rather than "no time
    /// at all" — a zero-length working day is never what anybody means.
    public static func span(start: Int, end: Int) -> Int {
        let raw = wrap(end) - wrap(start)
        let positive = (raw % minutesPerDay + minutesPerDay) % minutesPerDay
        return positive == 0 ? minutesPerDay : positive
    }

    /// Minutes from midnight, wrapped into 0..<1440 so out-of-range settings can't misbehave.
    public static func wrap(_ minute: Int) -> Int {
        (minute % minutesPerDay + minutesPerDay) % minutesPerDay
    }

    /// `Calendar` weekday number of the day before `weekday` (Sunday = 1 … Saturday = 7).
    public static func previousWeekday(_ weekday: Int) -> Int {
        weekday == 1 ? 7 : weekday - 1
    }

    // MARK: - Membership

    /// Whether `date` falls inside the user's office hours. Always true when the feature is off,
    /// so callers can use this unconditionally.
    public static func contains(_ date: Date, settings: Settings, calendar: Calendar = .current) -> Bool {
        guard settings.officeHoursEnabled else { return true }
        return contains(
            date,
            start: settings.officeHoursStart,
            end: settings.officeHoursEnd,
            days: settings.officeDays,
            calendar: calendar
        )
    }

    /// The window test itself. Two chances to be inside: the window that began today, and — for
    /// past-midnight windows — the one that began yesterday.
    public static func contains(
        _ date: Date,
        start: Int,
        end: Int,
        days: Set<Int>,
        calendar: Calendar = .current
    ) -> Bool {
        guard !days.isEmpty else { return false }
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        guard let hour = parts.hour, let minute = parts.minute, let weekday = parts.weekday else {
            return true
        }

        let begin = wrap(start)
        let length = span(start: start, end: end)
        let nowMinute = hour * 60 + minute

        let sinceTodaysStart = nowMinute - begin
        if sinceTodaysStart >= 0, sinceTodaysStart < length, days.contains(weekday) { return true }

        // Same offset measured from yesterday's start; only ever inside for overnight windows.
        let sinceYesterdaysStart = sinceTodaysStart + minutesPerDay
        if sinceYesterdaysStart < length, days.contains(previousWeekday(weekday)) { return true }

        return false
    }
}
