// TGMenuBar — the SwiftUI contents of the quick panel.
import SwiftUI
import TGCore

/// Two tabs behind one header. "Now" is the glance — one number, one obvious action, three
/// facts. "Stats" is the look back — today's stats and, behind the calendar button,
/// the month.
///
/// The Now tab is set like a ledger: an uppercase eyebrow, the time in a big serif, a hairline,
/// then facts on the left and actions on the right. Everything is left-aligned on purpose —
/// a centred stack of a symbol, a caption, a number and a row of pills is what every other
/// break app ships, and it reads as a dialog rather than as a page.
///
/// Deliberately sparse. Everything that isn't the countdown — pausing, the longer delays,
/// quitting — lives in the right-click menu, so the thing you open twenty times a day stays a
/// glance rather than a control panel.
struct QuickPanelView: View {

    @ObservedObject var engine: BreakEngine
    @ObservedObject var store: SettingsStore
    /// `nil` when the host didn't wire a stats store: the header falls back to the plain "Now"
    /// chip rather than offering a tab that leads nowhere.
    let stats: StatsStore?
    /// Navigation lives in the model, not in `@State`, so the host can open the panel onto a
    /// given tab and so the choice outlives a close/reopen.
    @ObservedObject var model: QuickPanelModel

    let actions: MenuBarActions
    /// Seconds until the next wellness nudge, when the host knows and the user asked for one.
    /// A closure rather than a value because the scheduler lives outside this module.
    var wellnessCountdown: () -> TimeInterval? = { nil }
    let dismiss: () -> Void
    /// The panel grows and shrinks between tabs; the window has to be told to re-measure.
    var requestResize: () -> Void = {}

    /// The one delay the panel offers. "+1m" and "+15m" live in the right-click menu: three
    /// pills in a column is a control panel, one is an escape hatch.
    private static let delaySeconds: TimeInterval = 5 * 60
    private static let sideWidth: CGFloat = 20
    /// Width of the action column. Wide enough for "Break now" at 14.5 pt, narrow enough that
    /// the facts beside it never wrap.
    private static let actionColumnWidth: CGFloat = 124

    var body: some View {
        VStack(spacing: 0) {
            topBar
            switch model.tab {
            case .now:
                nowTab
            case .stats:
                statsTab
            }
        }
        // 18 pt gutters give the ledger the margins of a set page — and land the content
        // column at exactly the 340 pt of the approved mock-up.
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
        // Warm wash over the glass, plus a whisper of grain: without it the material picks up
        // whatever is behind the panel and the whole thing reads gray.
        .background(TGPalette.glassWash)
        .paperGrain(opacity: 0.025)
        // Width is fixed; height is whatever the current state needs. `QuickPanel` reads the
        // fitting size when it shows the window — and again whenever the tab changes — so the
        // panel never has dead space at the bottom just because there is nothing to count down.
        .frame(width: QuickPanel.width, alignment: .top)
        .onChange(of: model.tab) { _, _ in requestResize() }
        .onChange(of: model.showingCalendar) { _, _ in requestResize() }
    }

    private var presentation: StatusPresentation {
        StatusPresentation(phase: engine.phase, style: .iconAndTime)
    }

    // MARK: - Top bar

    /// The Now/Stats control on the left margin — the same margin the eyebrow, the time and the
    /// facts start from — with the gear, and on the Stats tab the calendar toggle, on the right.
    /// A centred control over a left-aligned page is the one thing that would give the ledger away.
    private var topBar: some View {
        HStack(spacing: 10) {
            tabControl
            Spacer(minLength: 8)
            trailingSlot
            settingsButton
                .frame(width: Self.sideWidth, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var tabControl: some View {
        if stats == nil {
            Text("Now")
                .font(TGType.caption)
                .foregroundStyle(TGPalette.onMatcha)
                .padding(.vertical, 5)
                .padding(.horizontal, 20)
                .background(Capsule(style: .continuous).fill(TGPalette.matcha))
                .accessibilityAddTraits(.isHeader)
        } else {
            QuickPanelTabControl(tab: $model.tab)
        }
    }

    @ViewBuilder
    private var trailingSlot: some View {
        if model.tab == .stats, model.showingCalendar {
            iconButton(symbol: "arrow.left", label: "Back to today", size: 13) {
                model.showingCalendar = false
            }
        } else if model.tab == .stats {
            iconButton(symbol: "calendar", label: "Show the month", size: 13) {
                model.showingCalendar = true
            }
        }
    }

    private var settingsButton: some View {
        iconButton(symbol: "gearshape.fill", label: "Settings", size: 13.5, help: "Settings…") {
            dismiss()
            actions.openSettings()
        }
    }

    private func iconButton(
        symbol: String,
        label: String,
        size: CGFloat,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        IconButton(symbol: symbol, label: label, size: size, help: help,
                   diameter: Self.sideWidth, action: action)
    }

    // MARK: - Now tab

    private var nowTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow)
                .font(TGType.eyebrow)
                .tracking(TGType.eyebrowTracking)
                .foregroundStyle(TGPalette.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 16)
                .accessibilityAddTraits(.isHeader)
                // Caps and interpuncts are a typographic choice, not something to read out.
                .accessibilityLabel(eyebrow.capitalized.replacingOccurrences(of: " \u{B7} ", with: ", "))
            headline
                .padding(.top, 4)
            hairline
                .padding(.top, 14)
            ledger
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hairline: some View {
        Rectangle()
            .fill(TGPalette.stone)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    /// Facts on the left, actions on the right, a hair of stone between them.
    private var ledger: some View {
        HStack(alignment: .top, spacing: 14) {
            facts
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(TGPalette.stone)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            actionColumn
                .frame(width: Self.actionColumnWidth)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Stats tab

    @ViewBuilder
    private var statsTab: some View {
        if let stats {
            if model.showingCalendar {
                StatsCalendarView(stats: stats)
            } else {
                StatsView(stats: stats, settingsStore: store)
            }
        }
    }

    // MARK: - Eyebrow and headline

    /// The state, spelled out in caps above the number: "NEXT BREAK · SHORT · 30 SEC".
    /// Everything the old symbol-plus-caption stack said, in one line and a fifth of the height.
    private var eyebrow: String {
        switch engine.phase {
        case .stopped:
            return "STOPPED"
        case .inBreak:
            return "ON BREAK"
        case .waitingForActivityToStop:
            return "BREAK WAITING"
        case .paused(let reasons, _, _):
            let reason = StatusPresentation.primaryReason(reasons)
            let isManual: Bool = { if case .manual = reason { return true }; return false }()
            guard let reason, !isManual else { return "PAUSED" }
            return "PAUSED · \(reason.shortLabel.uppercased())"
        case .running, .preBreak:
            let kind = nextBreakKind
            return "NEXT BREAK · \(kind == .long ? "LONG" : "SHORT") · \(nextBreakLength.uppercased())"
        }
    }

    /// The big serif time — or, when there is nothing to count down, the reason why, set in
    /// italic at a quarter of the size. Same slot, opposite voice.
    @ViewBuilder
    private var headline: some View {
        if presentation.value.isEmpty {
            Text(presentation.detail)
                .font(TGType.ledgerReason)
                .foregroundStyle(TGPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .padding(.bottom, 2)
        } else {
            Text(presentation.value)
                .font(TGType.ledgerTime)
                .foregroundStyle(TGPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Fraunces carries a tall ascender and a deep descender that no digit uses,
                // so the line box is much larger than the ink. Trim it back, or the hairline
                // below floats away from the number.
                .padding(.top, -10)
                .padding(.bottom, -12)
        }
    }

    private var nextBreakLength: String {
        TGFormat.compact(
            nextBreakKind == .long
                ? store.settings.longBreakDuration
                : store.settings.shortBreakDuration
        )
    }

    // MARK: - Actions

    /// One primary and at most two quiet pills, stacked. A vertical column keeps every label
    /// readable at full size and stops the row of near-identical capsules that made the old
    /// panel look like a calculator.
    private var actionColumn: some View {
        VStack(spacing: 8) {
            primaryButton
            if engine.phase.isPaused {
                // Nothing to delay while paused, but starting a break by hand outranks the
                // pause — so offer that instead.
                Button("Break now") { actions.startBreak(nextBreakKind); dismiss() }
                    .buttonStyle(PillButtonStyle(fullWidth: true))
                    .help("Take a break now and resume the schedule")
            } else {
                if engine.canDelayNow {
                    Button("+5 min") { actions.delay(Self.delaySeconds) }
                        .buttonStyle(PillButtonStyle(fullWidth: true))
                        .help(delayHelp)
                }
                if showsSkip {
                    Button("Skip \u{203A}") { actions.skipOrEnd(); dismiss() }
                        .buttonStyle(PillButtonStyle(fullWidth: true))
                        .disabled(!engine.canSkipNow)
                        .help(engine.canSkipNow ? skipHelp : skipBlockedReason)
                }
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if engine.phase.isPaused {
            Button("Resume") { actions.resume(); dismiss() }
                .buttonStyle(PillButtonStyle(tier: .primary, fullWidth: true))
        } else if engine.phase.isInBreak {
            Button("End break") { actions.skipOrEnd(); dismiss() }
                .buttonStyle(PillButtonStyle(tier: .primary, fullWidth: true))
                .disabled(!engine.canSkipNow)
                .help(engine.canSkipNow ? skipHelp : skipBlockedReason)
        } else if engine.phase == .stopped {
            Button("Start") { actions.toggleRunning(); dismiss() }
                .buttonStyle(PillButtonStyle(tier: .primary, fullWidth: true))
                .help("Start TouchGrass")
        } else {
            Button("Break now") { actions.startBreak(nextBreakKind); dismiss() }
                .buttonStyle(PillButtonStyle(tier: .primary, fullWidth: true))
        }
    }

    /// Hardcore never skips, and a break that is already over has nothing left to skip; in
    /// every other state the pill stays put and explains itself, so the column doesn't jump
    /// height under the pointer.
    private var showsSkip: Bool {
        store.settings.enforcement != .hardcore
            && !engine.phase.isInBreak
            && engine.phase != .stopped
    }

    /// Says when a delay will cost a snooze, since that budget is finite and silent otherwise.
    private var delayHelp: String {
        guard engine.canSnoozeNow else { return "Push the break back 5 min" }
        let left = min(engine.snoozesRemainingToday, engine.snoozesRemainingThisSession)
        return "Push the break back 5 min · \(left) snooze\(left == 1 ? "" : "s") left"
    }

    /// Says how much budget is left when there is one, so the last skip of the day isn't a surprise.
    private var skipHelp: String {
        guard let left = engine.skipsRemainingToday else { return "End this break" }
        return "\(left) skip\(left == 1 ? "" : "s") left today"
    }

    private var skipBlockedReason: String {
        if engine.skipsRemainingToday == 0 { return "No skips left today" }
        // While the interval is still plainly counting there is no break in front of you yet —
        // say that, rather than blaming the enforcement level for it.
        if case .running = engine.phase { return "Nothing to skip until the break is due" }
        switch store.settings.enforcement {
        case .hardcore: return "Hardcore mode doesn't allow skipping"
        case .balanced: return "Skipping unlocks a few seconds into the break"
        case .casual: return "Nothing to skip right now"
        }
    }

    // MARK: - Facts

    /// Two or three lines of ledger: how long you've been at it, what today looks like, and —
    /// only when the user asked for nudges — when the next one lands.
    private var facts: some View {
        VStack(alignment: .leading, spacing: 11) {
            LedgerFact(label: "Focused", value: TGFormat.elapsed(engine.currentSessionFocusTime))
            LedgerFact(label: todayFact.label, value: todayFact.value)
            if let wellness = wellnessFact {
                LedgerFact(label: "Wellness", value: wellness)
            }
        }
        .padding(.top, 3)
    }

    /// With a stats store this is the day so far; without one there is nothing to look back on,
    /// so the slot says what's coming instead of sitting empty.
    private var todayFact: (label: String, value: String) {
        guard let stats else {
            return ("Next break", "\(nextBreakKind == .long ? "Long" : "Short") \u{B7} \(nextBreakLength)")
        }
        let day = stats.stats(for: Date())
        let taken = day.breaksTaken
        let breaks = "\(taken) break\(taken == 1 ? "" : "s")"
        // The stat of a day with nothing in it is an unearned 100; don't claim it.
        return ("Today", day.hasData ? "\(breaks) \u{B7} stat \(day.stats)" : breaks)
    }

    /// "Blink in 4 min". Named only when a single kind of nudge is switched on — the host hands
    /// over the soonest of blink, posture and the custom reminders, not which one it is.
    private var wellnessFact: String? {
        guard let seconds = wellnessCountdown(), seconds > 0 else { return nil }
        let settings = store.settings
        let onlyBlink = settings.blinkRemindersEnabled
            && !settings.postureRemindersEnabled
            && !settings.customReminders.contains(where: \.isSchedulable)
        let onlyPosture = settings.postureRemindersEnabled
            && !settings.blinkRemindersEnabled
            && !settings.customReminders.contains(where: \.isSchedulable)
        let what = onlyBlink ? "Blink" : (onlyPosture ? "Posture" : "Nudge")
        return "\(what) in \(TGFormat.minutes(seconds))"
    }

    private var nextBreakKind: BreakKind {
        switch engine.phase {
        case .running(let kind, _), .preBreak(let kind, _), .paused(_, let kind, _):
            return kind
        case .waitingForActivityToStop(let kind, _), .inBreak(let kind, _, _):
            return kind
        case .stopped:
            // Nothing scheduled — fall back to what the cadence says comes next.
            let settings = store.settings
            guard settings.longBreaksEnabled, settings.longBreakEvery > 0 else { return .short }
            return engine.shortBreaksSinceLong + 1 >= settings.longBreakEvery ? .long : .short
        }
    }
}
