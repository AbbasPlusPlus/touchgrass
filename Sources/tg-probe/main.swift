// tg-probe — live dump of everything TGDetection sees. Development tool, not shipped in the app.
//
//   .build/release/tg-probe            run until Ctrl-C
//   .build/release/tg-probe 15         run for 15 seconds
//   .build/release/tg-probe 30 --arm   also arm the typing/dragging detector
//   .build/release/tg-probe 20 --flip  toggle pauseOnVideo/pauseOnFullscreen off at t=6s, on at t=12s
//                                      (exercises live `settings` re-evaluation)
//
// Prints a full snapshot every 2 s and an immediate line whenever the merged output changes.
import AppKit
import Foundation
import TGCore
import TGDetection

@MainActor
final class Probe {

    static let shared = Probe()

    private let monitor = ActivityMonitor(settings: Settings())
    private var ticks = 0
    private var deadline: Date?
    private var lastSnapshot = ""

    func run(seconds: TimeInterval?, arm: Bool, flip: Bool) {
        deadline = seconds.map { Date().addingTimeInterval($0) }

        monitor.onChange = { reasons, hint in
            let labels = reasons.isEmpty ? "none" : reasons.map(\.shortLabel).sorted().joined(separator: ",")
            print("!! change  pauseReasons=[\(labels)] hint=\(hint?.rawValue ?? "nil")")
            fflush(stdout)
        }
        monitor.start()
        if arm { monitor.armActivityHints() }
        if flip {
            after(6) { self.setPauses(false) }
            after(12) { self.setPauses(true) }
        }

        print("tg-probe pid=\(ProcessInfo.processInfo.processIdentifier) — no TCC prompt should ever appear")
        dump()

        let timer = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { Probe.shared.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func after(_ delay: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        let t = Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { body() } }
        RunLoop.main.add(t, forMode: .common)
    }

    private func setPauses(_ enabled: Bool) {
        print(">> settings: pauseOnVideo/pauseOnFullscreen = \(enabled)")
        monitor.settings.pauseOnVideo = enabled
        monitor.settings.pauseOnFullscreen = enabled
    }

    private func tick() {
        ticks += 1
        dump()
        if let deadline, Date() >= deadline {
            print("── done after \(ticks) ticks ──")
            monitor.stop()
            exit(0)
        }
    }

    private func dump() {
        let snapshot = monitor.debugSnapshot()
        print(snapshot)
        // Highlight what moved since last time so a 15 s run is readable.
        if !lastSnapshot.isEmpty {
            let old = Set(lastSnapshot.split(separator: "\n").map(String.init))
            let new = snapshot.split(separator: "\n").map(String.init)
            let diff = new.filter { !old.contains($0) && !$0.hasPrefix("idle:") && !$0.hasPrefix("── ") }
            if !diff.isEmpty { print("   Δ " + diff.joined(separator: "\n   Δ ")) }
        }
        lastSnapshot = snapshot
        print("")
        fflush(stdout)
    }
}

let args = CommandLine.arguments.dropFirst()
let seconds = args.compactMap(Double.init).first
let arm = args.contains("--arm")
let flip = args.contains("--flip")

MainActor.assumeIsolated {
    Probe.shared.run(seconds: seconds, arm: arm, flip: flip)
}
RunLoop.main.run()
