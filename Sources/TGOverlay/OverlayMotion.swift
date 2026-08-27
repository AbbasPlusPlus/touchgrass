// TGOverlay — accessibility-aware motion & material policy.
// Every surface in this module asks OverlayMotion before it animates or blurs, so that
// Reduce Motion / Reduce Transparency are honoured in exactly one place.

import AppKit
import SwiftUI

public enum OverlayMotion {

    // MARK: - System preferences

    public static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    public static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    // MARK: - Durations

    /// Collapses a duration to zero when Reduce Motion is on.
    public static func duration(_ seconds: Double) -> Double {
        reduceMotion ? 0 : seconds
    }

    // MARK: - Curves

    /// The house easing curve: a soft exhale — slow out, slower in.
    public static func ease(_ seconds: Double) -> Animation {
        reduceMotion ? .linear(duration: 0) : .timingCurve(0.22, 0.61, 0.36, 1.0, duration: seconds)
    }

    /// A gentle, barely-overshooting spring. Used for anything that arrives.
    public static func softSpring(response: Double = 0.55, damping: Double = 0.86) -> Animation {
        reduceMotion ? .linear(duration: 0) : .spring(response: response, dampingFraction: damping)
    }

    // MARK: - Window fades

    /// Fades an `NSWindow`'s `alphaValue` on the main queue. Honours Reduce Motion.
    @MainActor
    public static func fade(_ window: NSWindow, to alpha: CGFloat, duration: Double,
                            completion: (() -> Void)? = nil) {
        let d = self.duration(duration)
        guard d > 0 else {
            window.alphaValue = alpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = d
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.61, 0.36, 1.0)
            ctx.allowsImplicitAnimation = true
            window.animator().alphaValue = alpha
        } completionHandler: {
            completion?()
        }
    }
}
