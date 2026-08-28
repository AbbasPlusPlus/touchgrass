// TGOverlay — notch metrics for a display.
// The Dynamic-Island pre-break banner fuses to the physical notch, so it needs the notch's
// width and height. On a non-notched display (or an external monitor) there is nothing to
// fuse with, so we hand back sensible fallbacks and let the caller decide whether to bother.

import AppKit

enum NotchGeometry {

    struct Metrics {
        /// True only when the display actually has a camera housing.
        var hasNotch: Bool
        /// Width of the black notch, in points.
        var notchWidth: CGFloat
        /// Height of the notch / menu-bar safe area, in points.
        var notchHeight: CGFloat
        /// The display this describes.
        var screen: NSScreen
    }

    /// Fallbacks used when a display has no notch, so the banner still renders in demos / on
    /// external monitors without special-casing every call site.
    static let fallbackWidth: CGFloat = 172
    static let fallbackHeight: CGFloat = 32

    static func metrics(for screen: NSScreen) -> Metrics {
        let top = screen.safeAreaInsets.top
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let hasNotch = top > 0 && (left > 0 || right > 0)

        let width = hasNotch ? max(0, screen.frame.width - left - right) : fallbackWidth
        let height = hasNotch ? top : fallbackHeight
        return Metrics(hasNotch: hasNotch, notchWidth: width, notchHeight: height, screen: screen)
    }

    /// The display to hang the banner from: the built-in notched screen if there is one,
    /// otherwise the screen under the pointer, otherwise main.
    static func preferredScreen(under mouse: NSScreen?) -> NSScreen {
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        return mouse ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }
}
