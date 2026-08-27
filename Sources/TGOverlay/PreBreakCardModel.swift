// TGOverlay — state for the T-60s notification card.

import Combine
import Foundation
import TGCore

@MainActor
final class PreBreakCardModel: ObservableObject {
    @Published var kind: BreakKind = .short
    @Published var secondsLeft: Int = 60
    @Published var copy: String = ""
    @Published var snoozesRemaining: Int = 0
    @Published var compact: Bool = false
    /// Drives the slide-in / slide-out. The panel itself never animates its frame.
    @Published var presented: Bool = false

    var onStart: () -> Void = {}
    var onSnooze: (TimeInterval) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    var countdownText: String {
        let clamped = max(0, secondsLeft)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    var eyebrow: String { kind == .long ? "Long break in" : "Break in" }

    static func randomCopy(for kind: BreakKind) -> String {
        let short = [
            "Almost time. Your eyes will appreciate this.",
            "Find a stopping point — this one is short.",
            "Nearly there. Twenty seconds of nothing.",
            "Wrap up the thought. The rest can wait.",
        ]
        let long = [
            "A longer one is coming. Good time for water.",
            "Almost time to stand up and look far away.",
            "Nearly there. Stretch something.",
            "A proper break next — save your place.",
        ]
        return (kind == .long ? long : short).randomElement() ?? short[0]
    }
}
