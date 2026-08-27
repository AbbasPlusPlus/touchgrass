// TGMenuBar — system-wide hotkeys via Carbon's RegisterEventHotKey.
// Deliberately NOT a CGEventTap: RegisterEventHotKey needs no Accessibility permission
// and no Input Monitoring prompt, which is a hard requirement for this app.
import AppKit
import Carbon.HIToolbox
import TGCore

/// Registers the user's global shortcuts and reports presses through `onAction`.
///
/// Carbon delivers hot key events on the main run loop, so the C trampoline below can
/// safely hop back onto the main actor with `assumeIsolated`.
@MainActor
public final class HotkeyManager {

    // MARK: Public

    /// Called on the main actor whenever a registered shortcut fires.
    public var onAction: ((HotkeyAction) -> Void)?

    public init() {}

    /// Replaces the whole registration set. Cheap enough to call on every settings change.
    public func reload(with hotkeys: [String: Hotkey]) {
        unregisterAll()
        installHandlerIfNeeded()

        for action in HotkeyAction.allCases {
            guard let hotkey = hotkeys[action.rawValue] else { continue }
            guard KeyGlyphs.hasRequiredModifier(hotkey.modifiers) else { continue }
            register(action, hotkey)
        }
    }

    /// Drops every registration and the Carbon handler. The manager normally lives for the
    /// whole process lifetime, so this exists mainly for tests and for teardown-on-quit.
    public func tearDown() {
        unregisterAll()
        if let handler = eventHandler { RemoveEventHandler(handler) }
        eventHandler = nil
    }

    public func unregisterAll() {
        for ref in registered.values { UnregisterEventHotKey(ref) }
        registered.removeAll()
        actionsByID.removeAll()
    }

    /// Looked up by the C trampoline.
    func handle(id: UInt32) {
        guard let action = actionsByID[id] else { return }
        onAction?(action)
    }

    // MARK: Private

    private var registered: [UInt32: EventHotKeyRef] = [:]
    private var actionsByID: [UInt32: HotkeyAction] = [:]
    private var eventHandler: EventHandlerRef?

    /// Four-char signature for our hot key IDs ('TGrs').
    private static let signature: OSType = 0x5447_7273

    private func register(_ action: HotkeyAction, _ hotkey: Hotkey) {
        // Index into `allCases` is a stable, collision-free ID within our signature.
        guard let index = HotkeyAction.allCases.firstIndex(of: action) else { return }
        let id = UInt32(index) + 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return }  // already taken by another app — stay quiet
        registered[id] = ref
        actionsByID[id] = action
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            tgHotkeyEventHandler,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        if status == noErr { eventHandler = handler }
    }
}

// MARK: - C trampoline

/// Carbon calls this on the main run loop; `userData` is the unretained `HotkeyManager`.
private func tgHotkeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { manager.handle(id: hotKeyID.id) }
    return noErr
}
