// TGMenuBar — "Custom reminders": water, stretch, eye drops, anything.
//
// One row per reminder — symbol, title, interval, on/off, remove — in the same inset card the
// message and app-list editors use, so the Wellness page stays one visual language.
import SwiftUI
import TGCore

struct CustomReminderListEditor: View {

    @Binding var reminders: [CustomReminder]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 0) {
                ForEach(reminders) { reminder in
                    row(reminder)
                    Divider()
                }
                addButton
            }
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(TGPalette.paper2.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(TGPalette.stone, lineWidth: 1)
            )
        }
    }

    // MARK: - Rows

    private func row(_ reminder: CustomReminder) -> some View {
        HStack(spacing: 6) {
            SymbolGridPicker(symbol: binding(reminder, \.symbol))

            TextField("Reminder", text: binding(reminder, \.title))
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(TGType.caption)

            Picker("", selection: binding(reminder, \.interval)) {
                ForEach(intervals(including: reminder.interval), id: \.self) { seconds in
                    Text(ReminderSymbols.intervalLabel(seconds)).tag(seconds)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 84)

            Toggle("", isOn: binding(reminder, \.enabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help(reminder.enabled ? "On" : "Off")

            Button {
                reminders.removeAll { $0.id == reminder.id }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(TGPalette.ink2)
            }
            .buttonStyle(.plain)
            .help("Remove this reminder")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
    }

    private var addButton: some View {
        HStack {
            Button {
                reminders.append(CustomReminder(title: "New reminder",
                                                symbol: ReminderSymbols.all.first ?? CustomReminder.defaultSymbol,
                                                interval: 45 * 60,
                                                enabled: true))
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add reminder")
                }
                .padding(.horizontal, 6)
                .frame(height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text(summary)
                .padding(.trailing, 9)
        }
        .font(TGType.footnote)
        .foregroundStyle(TGPalette.ink2)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private var summary: String {
        let on = reminders.filter(\.enabled).count
        if reminders.isEmpty { return "None yet" }
        return on == 0 ? "All off" : "\(on) on"
    }

    /// Keeps a hand-edited interval (from settings.json) selectable instead of snapping it away.
    private func intervals(including current: TimeInterval) -> [TimeInterval] {
        ReminderSymbols.intervals.contains(current)
            ? ReminderSymbols.intervals
            : (ReminderSymbols.intervals + [current]).sorted()
    }

    /// Bound by identity, not index: a row that is removed mid-edit resolves to its last known
    /// value instead of reading past the end of the array.
    private func binding<V>(_ reminder: CustomReminder, _ key: WritableKeyPath<CustomReminder, V>) -> Binding<V> {
        Binding(
            get: { (reminders.first { $0.id == reminder.id } ?? reminder)[keyPath: key] },
            set: { newValue in
                guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
                reminders[index][keyPath: key] = newValue
            }
        )
    }
}
