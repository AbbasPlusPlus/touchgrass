// TGMenuBar — the day as one strip: focus, pauses, breaks, now.
import AppKit
import SwiftUI
import TGCore

/// A 6am–midnight track of what the day actually looked like. Matcha bars are focus stretches,
/// clay ones ran past the user's own break interval, hatched ones are the time we stopped
/// judging (calls, videos, walks away), and the ticks are the breaks — ink for taken, clay for
/// skipped. A hairline marks now, on today only.
///
/// One Canvas rather than a stack of shapes: a day can hold two hundred spans, and a couple of
/// hundred `RoundedRectangle`s in a panel that reopens twenty times a day is a lot of view
/// identity for something that never animates.
struct RhythmTimelineView: View {

    let day: DayStats
    let settings: TGCore.Settings
    /// The day being drawn — the window is built from its midnight, not from `Date()`.
    let date: Date
    /// Wall clock for the "now" line, or `nil` on any day but today.
    var now: Date?

    private var calendar: Calendar { .current }

    // MARK: - Metrics

    private static let trackHeight: CGFloat = 34
    private static let trackRadius: CGFloat = 8
    private static let barInset: CGFloat = 6
    private static let barRadius: CGFloat = 4
    private static let tickWidth: CGFloat = 3
    private static let nowWidth: CGFloat = 1.5
    /// A one-minute session is a real fact about the day; give it enough width to be seen.
    private static let minimumBarWidth: CGFloat = 2
    private static let hatchSpacing: CGFloat = 7
    private static let hatchWidth: CGFloat = 3

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            track
            hourTicks
                .padding(.top, 5)
            legend
                .padding(.top, 8)
            factLine
                .padding(.top, 10)
        }
    }

    // MARK: - Track

    private var track: some View {
        Canvas(opaque: false) { context, size in
            let shape = Path(roundedRect: CGRect(origin: .zero, size: size),
                             cornerRadius: Self.trackRadius,
                             style: .continuous)
            context.fill(shape, with: .color(TGPalette.ink.opacity(0.05)))
            context.clip(to: shape)

            for bar in sessionBars {
                let rect = barRect(bar.span, in: size, inset: Self.barInset)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: Self.barRadius, style: .continuous),
                    with: .color(bar.isLong ? TGPalette.clay : TGPalette.matcha)
                )
            }

            for pause in pauseBars {
                hatch(barRect(pause.span, in: size, inset: Self.barInset), in: &context)
            }

            for tick in breakTicks {
                let x = tick.position * size.width - Self.tickWidth / 2
                let rect = CGRect(x: x, y: 1, width: Self.tickWidth, height: size.height - 2)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: Self.tickWidth / 2, style: .continuous),
                    with: .color(tick.skipped ? TGPalette.clay : TGPalette.ink)
                )
            }

            if let fraction = nowFraction {
                let x = fraction * size.width - Self.nowWidth / 2
                context.fill(
                    Path(CGRect(x: x, y: 0, width: Self.nowWidth, height: size.height)),
                    with: .color(TGPalette.ink.opacity(0.8))
                )
            }
        }
        .frame(height: Self.trackHeight)
        .overlay(hoverTargets)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    /// Invisible rectangles over the focus bars, purely so the pointer can ask a stretch when it
    /// was. `.help` is AppKit's own tooltip — no state, no timer, and it obeys the system delay.
    private var hoverTargets: some View {
        GeometryReader { proxy in
            ForEach(sessionBars) { bar in
                let rect = barRect(bar.span, in: proxy.size, inset: 0)
                Color.clear
                    .frame(width: max(rect.width, 6), height: proxy.size.height)
                    .contentShape(Rectangle())
                    .help(bar.help)
                    .position(x: rect.midX, y: proxy.size.height / 2)
            }
        }
        .accessibilityHidden(true)
    }

    /// Repeating 135° stripes, clipped to the bar: the pattern says "not counted" without
    /// introducing a fifth colour.
    private func hatch(_ rect: CGRect, in context: inout GraphicsContext) {
        var layer = context
        layer.clip(to: Path(roundedRect: rect, cornerRadius: Self.barRadius, style: .continuous))
        let ink = TGPalette.ink.opacity(0.22)
        var x = rect.minX - rect.height
        while x < rect.maxX {
            var line = Path()
            line.move(to: CGPoint(x: x, y: rect.minY))
            line.addLine(to: CGPoint(x: x + rect.height, y: rect.maxY))
            layer.stroke(line, with: .color(ink), lineWidth: Self.hatchWidth)
            x += Self.hatchSpacing
        }
    }

    private func barRect(_ span: ClosedRange<Double>, in size: CGSize, inset: CGFloat) -> CGRect {
        let x = span.lowerBound * size.width
        let width = max(Self.minimumBarWidth, (span.upperBound - span.lowerBound) * size.width)
        return CGRect(x: x, y: inset, width: width, height: size.height - inset * 2)
    }

    // MARK: - Hour ticks

    private var hourTicks: some View {
        GeometryReader { proxy in
            ForEach(tickHours, id: \.self) { hour in
                Text("\(hour)")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(TGPalette.ink2)
                    .position(x: tickX(hour, width: proxy.size.width), y: 7)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    private var tickHours: [Int] { Array(stride(from: windowStartHour, through: 24, by: 3)) }

    /// Nudged inside the track at both ends, so the first and last labels sit under the strip
    /// rather than hanging off it.
    private func tickX(_ hour: Int, width: CGFloat) -> CGFloat {
        let span = Double(24 - windowStartHour)
        let fraction = span > 0 ? Double(hour - windowStartHour) / span : 0
        return min(max(fraction * width, 6), width - 8)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Focus") { swatch(TGPalette.matcha) }
            legendItem("Long sit") { swatch(TGPalette.clay) }
            legendItem("Call \u{B7} away") { hatchSwatch }
            legendItem("Break") { tickSwatch }
        }
        .font(.system(size: 11.5, weight: .medium, design: .rounded))
        .foregroundStyle(TGPalette.ink2)
        .accessibilityHidden(true)
    }

    private func legendItem<Swatch: View>(
        _ title: String,
        @ViewBuilder swatch: () -> Swatch
    ) -> some View {
        HStack(spacing: 5) {
            swatch()
            Text(title)
        }
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color)
            .frame(width: 10, height: 10)
    }

    private var hatchSwatch: some View {
        Canvas { context, size in
            hatch(CGRect(origin: .zero, size: size), in: &context)
        }
        .frame(width: 10, height: 10)
    }

    private var tickSwatch: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(TGPalette.ink)
            .frame(width: 3, height: 10)
    }

    // MARK: - The sentence

    /// "Longest stretch **1h 47m**, 14:10–15:57 · **6** breaks · 1 skipped". Facts only: no
    /// adjective anywhere, and the skip clause disappears entirely when there were none.
    private var factLine: some View {
        Text(line)
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(TGPalette.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One `AttributedString` rather than concatenated `Text`s: the numbers step up to ink
    /// inside a sentence that stays quiet, and `Text` + `Text` is deprecated.
    private var line: AttributedString {
        var out = AttributedString()
        if let longest = longestSession, longest.duration >= 60 {
            let span = "\(Self.time(longest.start))\u{2013}\(Self.time(longest.end))"
            out += AttributedString("Longest stretch ")
            out += emphasised(TGFormat.compactElapsed(longest.duration))
            out += AttributedString(", \(span)")
        } else {
            out += AttributedString(day.hasData ? "No long stretches yet." : "Nothing recorded.")
        }

        let taken = day.breaksTaken
        if taken > 0 || day.breaksSkipped > 0 {
            out += AttributedString(" \u{B7} ")
            out += emphasised("\(taken)")
            out += AttributedString(" break\(taken == 1 ? "" : "s")")
            if day.breaksSkipped > 0 {
                out += AttributedString(" \u{B7} \(day.breaksSkipped) skipped")
            }
        }
        return out
    }

    private func emphasised(_ string: String) -> AttributedString {
        var part = AttributedString(string)
        part.foregroundColor = TGPalette.ink
        return part
    }

    private static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Window

    private var dayStart: Date { calendar.startOfDay(for: date) }

    /// 6am, unless the day started before it — then the top of the hour the first stretch began
    /// in, so an early start is never cropped out of its own timeline.
    private var windowStartHour: Int {
        let earliest = day.sessions.map(\.start).min()
        guard let earliest else { return 6 }
        let hour = calendar.component(.hour, from: earliest)
        guard calendar.isDate(earliest, inSameDayAs: dayStart) else { return 6 }
        return min(6, max(0, hour))
    }

    private var windowStart: Date { dayStart.addingTimeInterval(TimeInterval(windowStartHour) * 3600) }
    private var windowEnd: Date { dayStart.addingTimeInterval(24 * 3600) }

    private func fraction(_ date: Date) -> Double {
        let span = windowEnd.timeIntervalSince(windowStart)
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(windowStart) / span))
    }

    private func span(from start: Date, to end: Date) -> ClosedRange<Double> {
        let lower = fraction(start)
        return lower...max(lower, fraction(end))
    }

    private var nowFraction: Double? {
        guard let now, now >= windowStart, now <= windowEnd else { return nil }
        return fraction(now)
    }

    // MARK: - Laid-out spans

    private struct Bar: Identifiable {
        let id: Int
        let span: ClosedRange<Double>
        let isLong: Bool
        let help: String
    }

    private struct Tick: Identifiable {
        let id: Int
        let position: Double
        let skipped: Bool
    }

    private var sessionBars: [Bar] {
        let interval = settings.shortBreakInterval
        return sessionSpans.enumerated().map { index, session in
            let isLong = interval > 0 && session.duration > interval
            let label = isLong ? "Long sit" : "Focus"
            return Bar(
                id: index,
                span: span(from: session.start, to: session.drawnEnd),
                isLong: isLong,
                help: "\(label) \u{B7} \(TGFormat.compactElapsed(session.duration)) \u{B7} "
                    + "\(Self.time(session.start))\u{2013}\(Self.time(session.end))"
            )
        }
    }

    private var pauseBars: [Bar] {
        day.pauses.enumerated().map { index, pause in
            Bar(id: index,
                span: span(from: pause.start, to: pause.end),
                isLong: false,
                help: pause.kind.label)
        }
    }

    private var breakTicks: [Tick] {
        day.breaks.enumerated().map { index, record in
            Tick(id: index, position: fraction(record.at), skipped: record.outcome == .skipped)
        }
    }

    // MARK: - Session geometry

    /// A session's `duration` counts unpaused seconds only, so a stretch that held a twenty-minute
    /// call is drawn twenty minutes short of where it really ended — and the hatched bar for that
    /// call would land past its end. Push the drawn end out by the pauses that fall inside it, so
    /// the bar covers the ground the stretch actually covered.
    private struct DrawnSession {
        let start: Date
        let duration: TimeInterval
        let drawnEnd: Date
        var end: Date { start.addingTimeInterval(duration) }
    }

    private var sessionSpans: [DrawnSession] {
        let pauses = day.pauses.sorted { $0.start < $1.start }
        return day.sessions
            .filter { $0.duration > 0 }
            .sorted { $0.start < $1.start }
            .map { session in
                var end = session.start.addingTimeInterval(session.duration)
                // Strictly inside: a pause that begins exactly where the accrued seconds run out
                // came *after* the stretch, not during it, and must not stretch the bar over it.
                for pause in pauses where pause.start >= session.start && pause.start < end {
                    end = end.addingTimeInterval(pause.duration)
                }
                return DrawnSession(start: session.start, duration: session.duration, drawnEnd: end)
            }
    }

    private var longestSession: DrawnSession? {
        sessionSpans.max { $0.duration < $1.duration }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        guard day.hasData else { return "Rhythm: nothing recorded." }
        let stretches = sessionSpans.count
        var parts = ["\(stretches) stretch\(stretches == 1 ? "" : "es")"]
        if let longest = longestSession, longest.duration >= 60 {
            parts.append("longest \(TGFormat.elapsed(longest.duration))")
        }
        parts.append("\(day.breaksTaken) break\(day.breaksTaken == 1 ? "" : "s") taken")
        if day.breaksSkipped > 0 { parts.append("\(day.breaksSkipped) skipped") }
        return "Rhythm: " + parts.joined(separator: ", ")
    }
}
