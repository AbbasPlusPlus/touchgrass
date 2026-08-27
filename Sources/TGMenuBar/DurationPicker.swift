// TGMenuBar — a preset dropdown with a "Custom…" escape hatch, used for every duration.
import SwiftUI

/// Renders as a Form row: label on the left, a menu of presets on the right. Choosing
/// "Custom…" reveals a stepper underneath so the row stays a one-liner in the common case.
struct DurationPicker: View {

    enum Unit {
        case seconds
        case minutes

        var step: Int { self == .minutes ? 1 : 5 }
        var multiplier: TimeInterval { self == .minutes ? 60 : 1 }
        var suffix: String { self == .minutes ? "min" : "sec" }
    }

    let title: String
    @Binding var value: TimeInterval
    let presets: [TimeInterval]
    var unit: Unit = .minutes
    var bounds: ClosedRange<Int> = 1...480

    /// Sentinel tag for the "Custom…" menu entry — no real duration is negative.
    private static let customTag: TimeInterval = -1

    @State private var customRevealed = false

    var body: some View {
        Picker(title, selection: selection) {
            ForEach(presets, id: \.self) { preset in
                Text(label(preset)).tag(preset)
            }
            Divider()
            Text("Custom…").tag(Self.customTag)
        }

        if isCustom {
            LabeledContent("Custom length") {
                HStack(spacing: 6) {
                    TextField("", value: units, format: .number)
                        .frame(width: 56)
                        .multilineTextAlignment(.trailing)
                        .labelsHidden()
                    Stepper("", value: units, in: bounds, step: unit.step)
                        .labelsHidden()
                    Text(unit.suffix).foregroundStyle(TGPalette.ink2)
                }
            }
        }
    }

    // MARK: - Bindings

    private var isCustom: Bool { customRevealed || !presets.contains(value) }

    private var selection: Binding<TimeInterval> {
        Binding(
            get: { isCustom ? Self.customTag : value },
            set: { newValue in
                if newValue == Self.customTag {
                    customRevealed = true
                } else {
                    customRevealed = false
                    value = newValue
                }
            }
        )
    }

    /// The duration expressed in the picker's unit, clamped to `bounds`.
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
