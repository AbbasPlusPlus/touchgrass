// TGDetection — how long since the user last touched anything.
//
// `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType:)` needs no Accessibility
// and no Input Monitoring permission. `kCGAnyInputEventType` (0xFFFFFFFF) gives the combined idle time;
// querying `.keyDown` and the mouse events separately gives typing-vs-pointing without an event tap.
import CoreGraphics
import Foundation

@MainActor
public final class IdleDetector {

    /// Combined (any input) idle time in seconds.
    public private(set) var idleSeconds: TimeInterval = 0
    /// Seconds since the last key-down — the basis for typing detection.
    public private(set) var keyboardIdleSeconds: TimeInterval = 0
    /// Seconds since any mouse movement / click / scroll / drag.
    public private(set) var mouseIdleSeconds: TimeInterval = 0

    /// Mirrors `Settings.idlePauseAfter`; the poll tightens to 1 s past half of it so the threshold is
    /// crossed promptly instead of up to 5 s late.
    public var idlePauseAfter: TimeInterval = 120 {
        didSet { retune() }
    }
    /// Called whenever a value changed materially (≥ 0.5 s) or the idle/active state flipped.
    public var onChange: (@MainActor () -> Void)?

    public static let relaxedInterval: TimeInterval = 5
    public static let tightInterval: TimeInterval = 1

    private var poll: PollTimer?
    private var wasIdle = false

    public init() {}

    // MARK: Lifecycle

    public func start() {
        guard poll == nil else { return }
        let timer = PollTimer(interval: Self.relaxedInterval) { [weak self] in self?.refresh() }
        poll = timer
        timer.start()
        refresh()
    }

    public func stop() {
        poll?.stop()
        poll = nil
        idleSeconds = 0
        keyboardIdleSeconds = 0
        mouseIdleSeconds = 0
        wasIdle = false
    }

    /// Called after wake/unlock: the counters are meaningless across sleep.
    public func resetAndRefresh() {
        wasIdle = false
        refresh()
    }

    // MARK: Reading

    public func refresh() {
        let combined = Self.seconds(Self.anyInputEventType)
        let keyboard = Self.seconds(.keyDown)
        let mouse = [CGEventType.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged,
                     .rightMouseDragged, .scrollWheel, .otherMouseDown]
            .map(Self.seconds)
            .min() ?? combined

        let isIdle = combined >= idlePauseAfter
        let changed = abs(combined - idleSeconds) >= 0.5 || isIdle != wasIdle

        idleSeconds = combined
        keyboardIdleSeconds = keyboard
        mouseIdleSeconds = mouse
        wasIdle = isIdle

        retune()
        if changed { onChange?() }
    }

    /// 5 s while clearly active, 1 s once we're within striking distance of the pause threshold.
    private func retune() {
        guard let poll else { return }
        let tight = idleSeconds > max(1, idlePauseAfter / 2)
        poll.setInterval(tight ? Self.tightInterval : Self.relaxedInterval)
    }

    // MARK: CoreGraphics plumbing

    /// `kCGAnyInputEventType` == 0xFFFFFFFF. Guarded rather than force-unwrapped.
    static let anyInputEventType: CGEventType = CGEventType(rawValue: ~0) ?? .null

    static func seconds(_ type: CGEventType) -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
    }

    // MARK: Debug

    public func debugDescription() -> String {
        String(format: "idle: combined=%.1fs keyboard=%.1fs mouse=%.1fs (pauseAfter=%.0fs, poll=%.0fs)",
               idleSeconds, keyboardIdleSeconds, mouseIdleSeconds, idlePauseAfter, poll?.interval ?? 0)
    }
}
