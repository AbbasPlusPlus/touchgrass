// TGOverlay — the "screen blur" break background: frosts whatever the user was actually doing.
//
// Uses NSVisualEffectView with `.behindWindow` blending, so the window server composites the blur
// against every window beneath the overlay — no Screen Recording permission, nothing captured.
// A dark wash keeps the white break-screen text readable over arbitrarily bright content.
// Under Reduce Transparency the material goes flat, so we swap to the wallpaper treatment instead.

import SwiftUI
import AppKit
import TGCore

struct FrostBackgroundView: View {
    var body: some View {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            AmbientBackdropView(backdrop: .gradient(.dusk))
        } else {
            BehindWindowBlur()
                .overlay(Color.black.opacity(0.28))
                .overlay(
                    // A breath of vignette so edges recede and the center holds the eye.
                    RadialGradient(colors: [.clear, .black.opacity(0.18)],
                                   center: .center, startRadius: 300, endRadius: 1400)
                )
                .ignoresSafeArea()
        }
    }
}

struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .fullScreenUI
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
