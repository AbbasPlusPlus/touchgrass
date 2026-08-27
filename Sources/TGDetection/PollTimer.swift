// TGDetection — a repeating main-thread timer whose body is MainActor-isolated.
import Foundation

/// Thin wrapper over `Timer` so detectors don't each re-derive the isolation dance.
/// Timers scheduled here always fire on the main run loop, so `MainActor.assumeIsolated` is sound.
/// Generous `tolerance` lets the kernel coalesce wake-ups — important for idle CPU.
@MainActor
final class PollTimer {

    private var timer: Timer?
    private(set) var interval: TimeInterval
    private let toleranceFraction: Double
    private let action: @MainActor () -> Void

    init(interval: TimeInterval, toleranceFraction: Double = 0.2, action: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.toleranceFraction = toleranceFraction
        self.action = action
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Changes the cadence, restarting the timer only if the value actually moved.
    func setInterval(_ newValue: TimeInterval) {
        guard abs(newValue - interval) > 0.001 else { return }
        interval = newValue
        guard timer != nil else { return }
        stop()
        schedule()
    }

    private func schedule() {
        let action = self.action
        let t = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        t.tolerance = interval * toleranceFraction
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit { timer?.invalidate() }
}

/// One-shot main-thread callback (debounces, hysteresis deadlines).
@MainActor
final class OneShotTimer {

    private var timer: Timer?

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        cancel()
        let t = Timer(timeInterval: max(0.01, delay), repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        t.tolerance = min(0.25, delay * 0.1)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    var isScheduled: Bool { timer?.isValid ?? false }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }
}

// MARK: - Small shared helpers

/// FourCharCode → "bltn" for debug output.
func fourCharString(_ value: UInt32) -> String {
    guard value != 0 else { return "----" }
    let bytes = [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return String(format: "0x%08X", value) }
    return String(bytes: bytes, encoding: .ascii) ?? String(format: "0x%08X", value)
}

/// Runs `body` on the MainActor. Detector callbacks arrive on CoreAudio/CoreMediaIO queues.
func hopToMain(_ body: @escaping @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated { body() }
    } else {
        DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
    }
}
