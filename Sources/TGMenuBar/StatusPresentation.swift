// TGMenuBar — turns an EnginePhase into the strings every menu bar surface shows.
import Foundation
import TGCore

/// Pure derivation of display text from engine state. Keeping it separate from the views means
/// the status item, the quick panel header and the right-click menu can never disagree.
public struct StatusPresentation: Equatable {

    /// Text drawn next to the status item glyph. Empty means icon-only.
    public var menuBarText: String
    /// Whether the glyph should be drawn dimmed (paused / stopped).
    public var isDimmed: Bool
    /// Quick panel header, e.g. "Break starts in".
    public var headline: String
    /// The emphasised part of the header, e.g. "16:24". Empty when there is nothing to count.
    public var value: String
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
            symbol = "moon.zzz"
            tooltip = "TouchGrass is stopped"

        case .running(let kind, let remaining):
            menuBarText = TGFormat.clock(remaining)
            isDimmed = false
            headline = kind == .long ? "Long break starts in" : "Break starts in"
            value = TGFormat.clock(remaining)
            symbol = "hourglass"
            tooltip = "Next \(kind == .long ? "long " : "")break in \(TGFormat.duration(remaining))"

        case .preBreak(let kind, let remaining):
            menuBarText = TGFormat.clock(remaining)
            isDimmed = false
            headline = kind == .long ? "Long break starts in" : "Break starts in"
            value = TGFormat.clock(remaining)
            symbol = "hourglass.bottomhalf.filled"
            tooltip = "Break in \(TGFormat.duration(remaining))"

        case .waitingForActivityToStop(_, let hint):
            menuBarText = hint.label
            isDimmed = false
            headline = "Waiting until you're done"
            value = hint.label
            symbol = "keyboard"
            tooltip = "Break is waiting — \(hint.label)"

        case .inBreak(_, let remaining, _):
            menuBarText = "Break \(TGFormat.clock(remaining))"
            isDimmed = false
            headline = "On break"
            value = TGFormat.clock(remaining)
            symbol = "leaf"
            tooltip = "On break — \(TGFormat.clock(remaining)) left"

        case .paused(let reasons, _, _):
            // `.manual` already reads "Paused"; don't render "Paused · Paused".
            let reason = Self.primaryReason(reasons)
            let label: String = {
                guard let reason, case .manual = reason else {
                    return reason.map { "Paused · \($0.shortLabel)" } ?? "Paused"
                }
                return "Paused"
            }()
            menuBarText = label
            isDimmed = true
            headline = label
            value = ""
            symbol = "pause.circle"
            tooltip = Self.primaryReason(reasons)?.toastText ?? "Paused"
        }

        // The style only governs the *status item*; the panel always shows everything.
        switch style {
        case .iconOnly: menuBarText = ""
        case .timeOnly, .iconAndTime: break
        }
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
        case .idle: return 7
        }
    }
}
