// TGOverlay — stable identity for displays.
// NSScreen indices reshuffle on hot-plug; the display UUID does not. Every per-screen surface
// in this module is keyed by `ScreenID.uuid(for:)`.

import AppKit

public enum ScreenID {

    /// Stable identifier for a screen, surviving reconnects and index reshuffles.
    /// Falls back to the raw display number if CoreGraphics has no UUID (rare, e.g. ghost screens).
    public static func uuid(for screen: NSScreen) -> String {
        let displayID = self.displayID(for: screen)
        if let cf = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, cf) as String
        }
        return "display-\(displayID)"
    }

    public static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return 0 }
        return CGDirectDisplayID(number.uint32Value)
    }

    /// The screen the pointer is currently on. `NSScreen.main` lies when another app is fullscreen,
    /// so overlays that need "the user's screen" ask here instead.
    public static func screenUnderMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }
}
