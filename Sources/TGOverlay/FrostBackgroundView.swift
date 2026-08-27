// TGOverlay — the "screen blur" break background: frosts whatever the user was actually doing,
// then lays warm paper over it.
//
// Uses NSVisualEffectView with `.behindWindow` blending, so the window server composites the
// blur against every window beneath the overlay — no Screen Recording permission, nothing
// captured. The material follows the system appearance, and the wash on top is paper (light)
// or ink-green (dark), so the break screen reads as paper rather than as a grey scrim.
//
// Under Reduce Transparency the material goes flat, so we swap to plain paper instead.

import SwiftUI
import AppKit
import TGCore

struct FrostBackgroundView: View {

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            PaperBackgroundView()
        } else {
            BehindWindowBlur(dark: isDark)
                .overlay(isDark ? OverlayPalette.frostWashDark : OverlayPalette.frostWashLight)
                .overlay(PaperGrain(opacity: isDark ? 0.05 : 0.045))
                .ignoresSafeArea()
        }
    }
}

/// The Reduce-Transparency stand-in, and the flat end of the "screen blur" family: paper,
/// a whisper of a gradient so it isn't a dead field, and grain.
struct PaperBackgroundView: View {

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(colors: [OverlayPalette.paper2, OverlayPalette.paper],
                       startPoint: .top, endPoint: .bottom)
            .overlay(PaperGrain(opacity: colorScheme == .dark ? 0.05 : 0.045))
            .ignoresSafeArea()
    }
}

struct BehindWindowBlur: NSViewRepresentable {
    var dark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .fullScreenUI
        view.state = .active
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}
