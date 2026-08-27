// TGMenuBar — the S M T W T F S day picker used by the office-hours section.
import SwiftUI

/// Seven capsule chips, ordered by the user's first day of the week and labelled with the
/// locale's very-short weekday symbols. The binding holds `Calendar` weekday numbers (Sunday = 1),
/// which is what `Settings.officeDays` and `OfficeHours` speak.
struct WeekdayChipRow: View {

    @Binding var days: Set<Int>

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 4) {
            ForEach(orderedWeekdays, id: \.self) { weekday in
                chip(weekday)
            }
        }
    }

    private func chip(_ weekday: Int) -> some View {
        let isOn = days.contains(weekday)
        return Button {
            toggle(weekday)
        } label: {
            Text(shortSymbol(weekday))
                .font(TGType.caption)
                .foregroundStyle(isOn ? TGPalette.onMatcha : TGPalette.ink2)
                .frame(width: 24, height: 22)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? TGPalette.matcha : TGPalette.paper2)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help(fullSymbol(weekday))
        .accessibilityLabel(fullSymbol(weekday))
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func toggle(_ weekday: Int) {
        if days.contains(weekday) {
            days.remove(weekday)
        } else {
            days.insert(weekday)
        }
    }

    /// 1...7, rotated so the week starts where the user's calendar says it does.
    private var orderedWeekdays: [Int] {
        let first = calendar.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private func shortSymbol(_ weekday: Int) -> String {
        let symbols = calendar.veryShortWeekdaySymbols
        guard weekday >= 1, weekday <= symbols.count else { return "" }
        return symbols[weekday - 1]
    }

    private func fullSymbol(_ weekday: Int) -> String {
        let symbols = calendar.weekdaySymbols
        guard weekday >= 1, weekday <= symbols.count else { return "" }
        return symbols[weekday - 1]
    }
}
