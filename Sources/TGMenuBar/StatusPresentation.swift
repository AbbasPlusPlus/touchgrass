// TGMenuBar — turns an EnginePhase into the strings every menu bar surface shows.
import Foundation
import TGCore

/// Pure derivation of display text from engine state. Keeping it separate from the views means
/// the status item, the quick panel header and the right-click menu can never disagree.
///
/// Note the split between `menuBarText` (whole minutes, always) and `value` (a real `mm:ss`
/// clock). The status item is glanced at by accident all day; the quick panel is opened on
/// purpose. Only the second one gets to show seconds.
public struct StatusPresentation: Equatable {

    /// Text drawn next to the status item glyph. Minute-granular. Empty means icon-only.
    public var menuBarText: String
    /// Whether the glyph should be drawn dimmed (paused / stopped).
    public var isDimmed: Bool
    /// Quick panel caption above the countdown, e.g. "Break starts in".
    public var headline: String
    /// The big countdown, e.g. "22:51". Empty when there is nothing to count down.
    public var value: String
    /// Shown in place of `value` when there is no countdown — "Call detected on Zoom".
    public var detail: String
    /// SF Symbol for the quick panel header.
    public var symbol: String
    /// Tooltip on the status item.
    public var tooltip: String

    // MARK: - Derivation

    public init(phase: EnginePhase, style: MenuBarStyle) {
        switch phase {
        case .stopped:
            menuBarText = ""
            isDimmed = true
            headline = "TouchGrass is off"
            value = ""
            detail = "Not counting"
            symbol = "moon.zzz"
            tooltip = "TouchGrass is stopped"

        case .running(let kind, let remaining):
            menuBarText = TGFormat.menuBar(remaining)
            isDimmed = false
            headline = kind == .long ? "Long break starts in" : "Break starts in"
            value = TGFormat.clock(remaining)
            detail = ""
            symbol = "hourglass"
            tooltip = "Next \(kind == .long ? "long " : "")break in \(TGFormat.minutes(remaining))"

        case .preBreak(let kind, let remaining):
            menuBarText = TGFormat.menuBar(remaining)
            isDimmed = false
            headline = kind == .long ? "Long break starts in" : "Break starts in"
            value = TGFormat.clock(remaining)
            detail = ""
            symbol = "hourglass.bottomhalf.filled"
            tooltip = "Break in \(TGFormat.minutes(remaining))"

        case .waitingForActivityToStop(_, let hint):
            menuBarText = hint.label
            isDimmed = false
            headline = "Waiting until you're done"
            value = ""
            detail = hint.label
            symbol = "keyboard"
            tooltip = "Break is waiting — \(hint.label)"

        case .inBreak(_, let remaining, _):
            // The one place the status item is allowed a clock: you are already on the break,
            // so the seconds are the point rather than a nag.
            menuBarText = "Break · \(TGFormat.clock(remaining))"
            isDimmed = false
            headline = "On break"
            value = TGFormat.clock(remaining)
            detail = ""
            symbol = "leaf"
            tooltip = "On break — \(TGFormat.clock(remaining)) left"

        case .paused(let reasons, _, let remaining):
            // `.manual` already reads "Paused"; don't render "Paused · Paused".
            let reason = Self.primaryReason(reasons)
            let isManual: Bool = { if case .manual = reason { return true }; return false }()
            let label = isManual ? "Paused" : (reason.map { "Paused · \($0.shortLabel)" } ?? "Paused")
            menuBarText = label
            isDimmed = true
            headline = label
            value = ""
            detail = isManual
                ? "\(TGFormat.minutes(remaining)) left when you resume"
                : (reason?.toastText ?? "Paused")
            symbol = "pause.circle"
            tooltip = reason?.toastText ?? "Paused"
        }

        // The style only governs the *status item*; the panel always shows everything.
        switch style {
        case .iconOnly: menuBarText = ""
        case .timeOnly, .iconAndTime: break
        }
    }

    /// Everything the status item actually draws. The quick panel's countdown changes every
    /// second; the status item must not repaint that often, so `StatusBarController` diffs
    /// this instead of the whole presentation.
    public var statusItemKey: String {
        "\(menuBarText)\u{1F}\(isDimmed)\u{1F}\(tooltip)"
    }

    /// Whether the status item should draw the glyph at all.
    public static func showsIcon(for style: MenuBarStyle) -> Bool { style != .timeOnly }

    /// Picks the most informative reason to name in a one-line label.
    /// Manual pauses win (the user did it deliberately), then meetings, then everything else.
    public static func primaryReason(_ reasons: Set<PauseReason>) -> PauseReason? {
        let ranked = reasons.sorted { rank($0) < rank($1) }
        return ranked.first
    }

    private static func rank(_ reason: PauseReason) -> Int {
        switch reason {
        case .manual: return 0
        case .meeting: return 1
        case .video: return 2
        case .deepFocusApp: return 3
        case .fullscreenApp: return 4
        case .screenLocked: return 5
        case .focusMode: return 6
        // Off hours outranks idle: at 7pm "Off hours" explains the state, "Away" merely restates it.
        case .outsideOfficeHours: return 7
        case .idle: return 8
        }
    }
}
