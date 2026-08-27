// TGMenuBar — the SwiftUI contents of the quick panel.
import SwiftUI
import TGCore

/// "Now" at a glance: what's next, four things you can do about it, and the state that
/// explains the number at the top.
struct QuickPanelView: View {

    @ObservedObject var engine: BreakEngine
    @ObservedObject var store: SettingsStore

    let actions: MenuBarActions
    let wellnessCountdown: () -> TimeInterval?
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            actionPills
            summaryList
            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        // Width is fixed; height is whatever the current state needs. `QuickPanel` reads the
        // fitting size when it shows the window, so the panel never has dead space at the
        // bottom just because wellness reminders happen to be off.
        .frame(width: QuickPanel.width, alignment: .top)
    }

    // MARK: - Header

    private var presentation: StatusPresentation {
        StatusPresentation(phase: engine.phase, style: .iconAndTime)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: presentation.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.accentColor.opacity(0.14)))

            VStack(alignment: .leading, spacing: 1) {
                Text(presentation.headline)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                if presentation.value.isEmpty {
                    Text(pausedDetail)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                } else {
                    Text(presentation.value)
                        .font(.system(size: 24, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// When there's no countdown to show (paused / stopped) the header still needs a second line.
    private var pausedDetail: String {
        switch engine.phase {
        case .stopped: return "Not counting"
        case .paused(let reasons, _, let remaining):
            let reason = StatusPresentation.primaryReason(reasons)
            if case .manual = reason { return "\(TGFormat.duration(remaining)) left when you resume" }
            return reason?.toastText ?? "Paused"
        default: return ""
        }
    }

    // MARK: - Actions

    private var actionPills: some View {
        HStack(spacing: 8) {
            if engine.phase.isPaused {
                Button("Resume") { actions.resume(); dismiss() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                Button("Start break") { actions.startBreak(.short); dismiss() }
                    .buttonStyle(PillButtonStyle())
            } else if engine.phase.isInBreak {
                Button("End break") { actions.skipOrEnd(); dismiss() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(!engine.canSkipNow)
                Button("+1m") { actions.snooze(60) }
                    .buttonStyle(PillButtonStyle())
                Button("+5m") { actions.snooze(5 * 60) }
                    .buttonStyle(PillButtonStyle())
            } else {
                Button("Start break") { actions.startBreak(.short); dismiss() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                Button("+1m") { actions.snooze(60) }
                    .buttonStyle(PillButtonStyle())
                Button("+5m") { actions.snooze(5 * 60) }
                    .buttonStyle(PillButtonStyle())
                Button("Skip") { actions.skipOrEnd(); dismiss() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(!engine.canSkipNow)
                    .help(engine.canSkipNow ? "Skip this break" : skipBlockedReason)
            }
        }
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
        VStack(spacing: 0) {
            QuickPanelRow(
                symbol: "display",
                title: "Current focus time",
                value: TGFormat.duration(engine.currentSessionFocusTime)
            )
            Divider().padding(.leading, 38)
            QuickPanelRow(
                symbol: "arrow.right.circle",
                title: "Upcoming break",
                value: upcomingBreakSummary
            )
            Divider().padding(.leading, 38)
            QuickPanelRow(
                symbol: "zzz",
                title: "Snoozes left",
                value: snoozeSummary
            )
            if store.settings.blinkRemindersEnabled || store.settings.postureRemindersEnabled {
                Divider().padding(.leading, 38)
                QuickPanelRow(
                    symbol: "eye",
                    title: "Wellness",
                    value: wellnessSummary
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private var upcomingBreakSummary: String {
        let settings = store.settings
        let kind = nextBreakKind
        let duration = kind == .long ? settings.longBreakDuration : settings.shortBreakDuration
        return "\(kind == .long ? "Long" : "Short") · \(TGFormat.duration(duration))"
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

    private var snoozeSummary: String {
        "\(engine.snoozesRemainingToday) today, \(engine.snoozesRemainingThisSession) this session"
    }

    private var wellnessSummary: String {
        let settings = store.settings
        if settings.blinkRemindersEnabled {
            if let next = wellnessCountdown() { return "Blink \(TGFormat.relative(next))" }
            return "Blink every \(TGFormat.compact(settings.blinkReminderInterval))"
        }
        return "Posture every \(TGFormat.compact(settings.postureReminderInterval))"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                dismiss()
                actions.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings…")

            Menu {
                if engine.phase.isPaused {
                    Button("Resume") { actions.resume(); dismiss() }
                } else {
                    ForEach(Array(PausePreset.allCases.enumerated()), id: \.offset) { _, preset in
                        Button(preset.title) {
                            actions.pause(preset.duration())
                            dismiss()
                        }
                    }
                }
            } label: {
                Label(engine.phase.isPaused ? "Paused" : "Pause", systemImage: "pause.circle")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer(minLength: 0)

            Button {
                dismiss()
                actions.quit()
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit TouchGrass")
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
    }
}
