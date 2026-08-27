// TGMenuBar — the SwiftUI contents of the quick panel.
import SwiftUI
import TGCore

/// "Now" at a glance: one number, one obvious action, and two facts underneath.
///
/// Deliberately sparse. Everything that isn't the countdown — pausing, quitting, the snooze
/// budget — lives in the right-click menu, so the thing you open twenty times a day stays a
/// glance rather than a control panel.
struct QuickPanelView: View {

    @ObservedObject var engine: BreakEngine
    @ObservedObject var store: SettingsStore

    let actions: MenuBarActions
    let dismiss: () -> Void

    /// "+1m / +5m / +15m", in minutes.
    private static let delayOptions = [1, 5, 15]
    private static let gearWidth: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            topBar
            countdown
                .padding(.top, 16)
            actionPills
                .padding(.top, 18)
            summaryList
                .padding(.top, 18)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        // Width is fixed; height is whatever the current state needs. `QuickPanel` reads the
        // fitting size when it shows the window, so the panel never has dead space at the
        // bottom just because there is nothing to count down.
        .frame(width: QuickPanel.width, alignment: .top)
    }

    private var presentation: StatusPresentation {
        StatusPresentation(phase: engine.phase, style: .iconAndTime)
    }

    // MARK: - Top bar

    /// A single "Now" chip, centred, with the gear tucked into the trailing corner. 
    /// puts a Now/Stats segmented control here; we have no Stats surface yet, so the chip is
    /// a label rather than a control that pretends to switch something.
    private var topBar: some View {
        HStack(spacing: 0) {
            // A mirror of the gear's width, so the chip sits optically centred without a
            // ZStack — which sizes to its largest child and quietly drops the trailing button.
            Color.clear.frame(width: Self.gearWidth, height: 1)
            Spacer(minLength: 8)

            Text("Now")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.vertical, 4)
                .padding(.horizontal, 18)
                .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.13)))
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)
            Button {
                dismiss()
                actions.openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.gearWidth, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings…")
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Countdown

    private var countdown: some View {
        VStack(spacing: 5) {
            Image(systemName: presentation.symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
            Text(presentation.headline)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if presentation.value.isEmpty {
                Text(presentation.detail)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            } else {
                Text(presentation.value)
                    .font(.system(size: 44, weight: .bold))
                    .monospacedDigit()
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
                .help(engine.canSkipNow ? "End this break" : skipBlockedReason)
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

    private var skipBlockedReason: String {
        switch store.settings.enforcement {
        case .hardcore: return "Hardcore mode doesn't allow skipping"
        case .balanced: return "Skipping unlocks a few seconds into the break"
        case .casual: return "Nothing to skip right now"
        }
    }

    // MARK: - Summary

    private var summaryList: some View {
        VStack(spacing: 6) {
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
