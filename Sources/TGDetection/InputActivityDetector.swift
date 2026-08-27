// TGDetection — "the user is mid-keystroke / mid-drag, don't drop an overlay on them".
//
// Only ever runs in the last seconds before a break: the app calls `arm()` around T-15 s and
// `disarm()` once the break starts. Disarmed it costs literally nothing (no timer at all).
import CoreGraphics
import Foundation
import TGCore

@MainActor
public final class InputActivityDetector {

    /// A key-down within this window means "still typing".
    public static let typingWindow: TimeInterval = 2
    /// Dragging is a tighter window — a drag in progress is continuous.
    public static let draggingWindow: TimeInterval = 1

    public private(set) var isArmed = false
    /// `.typing` / `.dragging`, or nil.
    public private(set) var hint: ActivityHint?

    public var onChange: (@MainActor () -> Void)?

    private var poll: PollTimer?

    public init() {}

    // MARK: Arming

    public func arm() {
        guard !isArmed else { return }
        isArmed = true
        let timer = PollTimer(interval: 1, toleranceFraction: 0.1) { [weak self] in self?.refresh() }
        poll = timer
        timer.start()
        refresh()
    }

    public func disarm() {
        guard isArmed else { return }
        isArmed = false
        poll?.stop()
        poll = nil
        if hint != nil {
            hint = nil
            onChange?()
        }
    }

    public func stop() { disarm() }

    // MARK: Reading

    private func refresh() {
        let dragging = min(IdleDetector.seconds(.leftMouseDragged), IdleDetector.seconds(.rightMouseDragged))
        let typing = IdleDetector.seconds(.keyDown)

        // Dragging first: a drag in flight is the more disruptive thing to interrupt.
        let newHint: ActivityHint? = dragging < Self.draggingWindow ? .dragging
            : (typing < Self.typingWindow ? .typing : nil)

        guard newHint != hint else { return }
        hint = newHint
        onChange?()
    }

    // MARK: Debug

    public func debugDescription() -> String {
        guard isArmed else { return "input: disarmed" }
        return String(format: "input: armed hint=%@ sinceKeyDown=%.1fs sinceDrag=%.1fs",
                      hint?.rawValue ?? "nil",
                      IdleDetector.seconds(.keyDown),
                      min(IdleDetector.seconds(.leftMouseDragged), IdleDetector.seconds(.rightMouseDragged)))
    }
}
