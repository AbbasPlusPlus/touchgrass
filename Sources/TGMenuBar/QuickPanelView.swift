// TGMenuBar — the SwiftUI contents of the quick panel.
import SwiftUI
import TGCore

/// Two tabs behind one header. "Now" is the glance — one number, one obvious action, two facts.
/// "Stats" is the look back — today's stats and, behind the calendar button, the month.
///
/// Deliberately sparse. Everything that isn't the countdown — pausing, quitting, the snooze
/// budget — lives in the right-click menu, so the thing you open twenty times a day stays a
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
    let dismiss: () -> Void
    /// The panel grows and shrinks between tabs; the window has to be told to re-measure.
    var requestResize: () -> Void = {}

    /// "+1m / +5m / +15m", in minutes.
    private static let delayOptions = [1, 5, 15]
    private static let sideWidth: CGFloat = 20

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
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
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

    /// The Now/Stats control, centred, with the gear in the trailing corner and — on the Stats
    /// tab — the calendar toggle in the leading one.
    private var topBar: some View {
        HStack(spacing: 0) {
            // A fixed leading slot mirrors the gear's width, so the control sits optically
            // centred without a ZStack — which sizes to its largest child and quietly drops
            // the trailing button.
            leadingSlot
                .frame(width: Self.sideWidth, alignment: .leading)
            Spacer(minLength: 8)
            tabControl
            Spacer(minLength: 8)
            settingsButton
                .frame(width: Self.sideWidth, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var tabControl: some View {
        if stats == nil {
            Text("Now")
                .font(TGType.caption)
                .foregroundStyle(.primary)
                .padding(.vertical, 5)
                .padding(.horizontal, 20)
                .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.13)))
                .accessibilityAddTraits(.isHeader)
        } else {
            QuickPanelTabControl(tab: $model.tab)
        }
    }

    @ViewBuilder
    private var leadingSlot: some View {
        if model.tab == .stats, model.showingCalendar {
            iconButton(symbol: "arrow.left", label: "Back to today", size: 13) {
                model.showingCalendar = false
            }
        } else if model.tab == .stats {
            iconButton(symbol: "calendar", label: "Show the month", size: 13) {
                model.showingCalendar = true
            }
        } else {
            Color.clear.frame(width: Self.sideWidth, height: 1)
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
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(.secondary)
                .frame(width: Self.sideWidth, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help ?? label)
        .accessibilityLabel(label)
    }

    // MARK: - Now tab

    private var nowTab: some View {
        VStack(spacing: 0) {
            countdown
                .padding(.top, 16)
            actionPills
                .padding(.top, 18)
            summaryList
                .padding(.top, 18)
        }
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

    // MARK: - Countdown

    private var countdown: some View {
        VStack(spacing: 6) {
            Image(systemName: presentation.symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.secondary)
            Text(presentation.headline)
                .font(TGType.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if presentation.value.isEmpty {
                Text(presentation.detail)
                    .font(TGType.title)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            } else {
                Text(presentation.value)
                    .font(TGType.hero)
                    .foregroundStyle(.primary)
                    .padding(.top, -2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private var actionPills: some View {
        HStack(spacing: 8) {
            primaryButton
            if engine.phase.isPaused {
                // Nothing to delay while paused, but starting a break by hand outranks the
                // pause — so offer that instead.
                Button("Start break") { actions.startBreak(nextBreakKind); dismiss() }
                    .buttonStyle(PillButtonStyle())
            } else if showsDelayPills {
                ForEach(Self.delayOptions, id: \.self) { minutes in
                    Button("+\(minutes)m") { actions.delay(TimeInterval(minutes) * 60) }
                        .buttonStyle(PillButtonStyle())
                        .help("Push the break back \(minutes) min")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var primaryButton: some View {
        if engine.phase.isPaused {
            Button("Resume") { actions.resume(); dismiss() }
                .buttonStyle(PillButtonStyle(tier: .primary))
        } else if engine.phase.isInBreak {
            Button("End break") { actions.skipOrEnd(); dismiss() }
                .buttonStyle(PillButtonStyle(tier: .primary))
                .disabled(!engine.canSkipNow)
                .help(engine.canSkipNow ? skipHelp : skipBlockedReason)
        } else if engine.phase == .stopped {
            Button("Start TouchGrass") { actions.toggleRunning(); dismiss() }
                .buttonStyle(PillButtonStyle(tier: .primary))
        } else {
            Button("Start break") { actions.startBreak(nextBreakKind); dismiss() }
                .buttonStyle(PillButtonStyle(tier: .primary))
        }
    }

    /// Delaying spends the snooze budget, so the pills disappear rather than sit there dead
    /// once it's gone — running out is the point of the budget.
    private var showsDelayPills: Bool {
        engine.canDelayNow && engine.hasSnoozeBudget
    }

    /// Says how much budget is left when there is one, so the last skip of the day isn't a surprise.
    private var skipHelp: String {
        guard let left = engine.skipsRemainingToday else { return "End this break" }
        return "\(left) skip\(left == 1 ? "" : "s") left today"
    }

    private var skipBlockedReason: String {
        if engine.skipsRemainingToday == 0 { return "No skips left today" }
        switch store.settings.enforcement {
        case .hardcore: return "Hardcore mode doesn't allow skipping"
        case .balanced: return "Skipping unlocks a few seconds into the break"
        case .casual: return "Nothing to skip right now"
        }
    }

    // MARK: - Summary

    private var summaryList: some View {
        VStack(spacing: 7) {
            QuickPanelRow(
                symbol: "bolt.fill",
                tint: .yellow,
                title: "Current focus time",
                value: TGFormat.elapsed(engine.currentSessionFocusTime)
            )
            QuickPanelRow(
                symbol: "figure.mind.and.body",
                tint: .pink,
                title: "Upcoming break",
                accent: nextBreakKind == .long ? "Long" : "Short",
                value: TGFormat.duration(
                    nextBreakKind == .long
                        ? store.settings.longBreakDuration
                        : store.settings.shortBreakDuration
                )
            )
        }
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
