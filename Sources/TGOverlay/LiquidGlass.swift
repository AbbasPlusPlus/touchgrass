// TGOverlay — the one place that knows Liquid Glass is a macOS 26 material.
//
// Every glass surface in this module was built with a flat paper twin for Reduce Transparency.
// That twin is also what macOS 15–15.x gets: `isUsable` folds the OS check into the same
// question the surfaces already asked, so there is one branch per surface, not two.

import AppKit
import SwiftUI

enum LiquidGlass {

    /// True when the system can draw Liquid Glass *and* the user hasn't asked for less of it.
    static var isUsable: Bool {
        if OverlayMotion.reduceTransparency { return false }
        if #available(macOS 26, *) { return true }
        return false
    }
}

extension View {

    /// `.glassEffect` where the OS has it.
    ///
    /// Only reachable behind `LiquidGlass.isUsable`, so the pass-through arm never actually
    /// renders — below macOS 26 the caller has already taken its paper branch.
    @ViewBuilder
    func liquidGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self
        }
    }
}
