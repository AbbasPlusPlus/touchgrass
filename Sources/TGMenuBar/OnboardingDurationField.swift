// TGMenuBar — preset chips with a Custom escape hatch, for the first-run duration questions.
import SwiftUI

/// A row of preset chips plus a "Custom…" chip that reveals a stepper underneath.
///
/// Onboarding used to be presets-only, which quietly told anyone who wanted a 12-minute
/// interval that the app wasn't for them.  lets you set any duration during setup;
/// so does this. The common case is still one click.
struct OnboardingDurationField: View {

    let presets: [TimeInterval]
    @Binding var value: TimeInterval
    var unit: DurationPicker.Unit = .minutes
    var bounds: ClosedRange<Int> = 1...480

    @State private var customRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { preset in
                    chip(label(preset), selected: !isCustom && value == preset) {
                        customRevealed = false
                        value = preset
                    }
                }
                chip("Custom…", selected: isCustom) {
                    customRevealed = true
                }
            }

            if isCustom { customField }
        }
        .animation(.easeInOut(duration: 0.15), value: isCustom)
    }

    // MARK: - Chips

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(selected ? TGType.pill : TGType.pillQuiet)
                .lineLimit(1)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? Color.accentColor : Color.primary.opacity(0.07))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(selected ? 0 : 0.10), lineWidth: 1)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Custom value

    private var customField: some View {
        HStack(spacing: 6) {
            TextField("", value: units, format: .number)
                .frame(width: 54)
                .multilineTextAlignment(.trailing)
                .labelsHidden()
            Stepper("", value: units, in: bounds, step: unit.step)
                .labelsHidden()
            Text(unit.suffix)
                .font(TGType.body)
                .foregroundStyle(.secondary)

            // A rest of 150 sec is easier to picture as "2 min 30 sec".
            if unit == .seconds, value >= 60 {
                Text("· \(TGFormat.compact(value))")
                    .font(TGType.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityLabel("Custom length in \(unit.suffix)")
    }

    // MARK: - Bindings

    /// A value the chips can't express is custom by definition, whether or not the user asked.
    private var isCustom: Bool { customRevealed || !presets.contains(value) }

    /// The duration expressed in the field's unit, clamped to `bounds`.
    private var units: Binding<Int> {
        Binding(
            get: { Int((value / unit.multiplier).rounded()) },
            set: { value = TimeInterval(min(max($0, bounds.lowerBound), bounds.upperBound)) * unit.multiplier }
        )
    }

    private func label(_ seconds: TimeInterval) -> String {
        switch unit {
        case .minutes: return "\(Int(seconds / 60)) min"
        case .seconds: return "\(Int(seconds)) sec"
        }
    }
}
