// TGMenuBar — turning virtual key codes + Carbon modifier masks into ⌃⌥⇧⌘K glyph strings.
import AppKit
import Carbon.HIToolbox
import TGCore

/// Formatting helpers shared by `ShortcutRecorderView` and the right-click menu.
public enum KeyGlyphs {

    // MARK: - Modifiers

    /// Carbon modifier mask → glyphs, in Apple's canonical order (⌃⌥⇧⌘).
    public static func modifierString(carbon: UInt32) -> String {
        var out = ""
        if carbon & UInt32(controlKey) != 0 { out += "⌃" }
        if carbon & UInt32(optionKey)  != 0 { out += "⌥" }
        if carbon & UInt32(shiftKey)   != 0 { out += "⇧" }
        if carbon & UInt32(cmdKey)     != 0 { out += "⌘" }
        return out
    }

    /// `NSEvent.ModifierFlags` → Carbon mask, keeping only the four we register with.
    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }

    /// A shortcut needs at least one of ⌘ ⌃ ⌥ to be safe to register globally
    /// (⇧ alone would swallow every capital letter the user types).
    public static func hasRequiredModifier(_ carbon: UInt32) -> Bool {
        carbon & (UInt32(cmdKey) | UInt32(controlKey) | UInt32(optionKey)) != 0
    }

    // MARK: - Keys

    /// Full "⌃⌥⌘K" rendering of a stored hotkey.
    public static func display(_ hotkey: Hotkey) -> String {
        modifierString(carbon: hotkey.modifiers) + keyString(hotkey.keyCode)
    }

    /// Virtual key code → the glyph printed on the key.
    public static func keyString(_ keyCode: UInt32) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        if let letter = layoutIndependentKeys[Int(keyCode)] { return letter }
        return "?"
    }

    // MARK: - Tables

    /// Non-printing keys, named the way macOS menus name them.
    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_ANSI_KeypadEnter: "⌤", kVK_Help: "?⃝",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// ANSI positions. We store the *position*, so the glyph shown is the US-layout label —
    /// which is also what Carbon's `RegisterEventHotKey` binds to.
    private static let layoutIndependentKeys: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Grave: "`",
        kVK_ANSI_Keypad0: "0", kVK_ANSI_Keypad1: "1", kVK_ANSI_Keypad2: "2",
        kVK_ANSI_Keypad3: "3", kVK_ANSI_Keypad4: "4", kVK_ANSI_Keypad5: "5",
        kVK_ANSI_Keypad6: "6", kVK_ANSI_Keypad7: "7", kVK_ANSI_Keypad8: "8",
        kVK_ANSI_Keypad9: "9", kVK_ANSI_KeypadDecimal: ".", kVK_ANSI_KeypadMultiply: "*",
        kVK_ANSI_KeypadPlus: "+", kVK_ANSI_KeypadMinus: "-", kVK_ANSI_KeypadDivide: "/",
        kVK_ANSI_KeypadEquals: "=", kVK_ANSI_KeypadClear: "⌧",
    ]
}
