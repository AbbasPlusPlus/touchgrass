// TGMenuBar — the click-to-record shortcut field used on the Keyboard Shortcuts page.
import AppKit
import Carbon.HIToolbox
import SwiftUI
import TGCore

/// A System-Settings-style shortcut well: click it, type a combination, or click × to clear.
///
/// Recording uses a *local* NSEvent monitor, so it only sees keys while the settings window
/// is key — it can never swallow keystrokes meant for another app.
public struct ShortcutRecorderView: View {

    @Binding public var hotkey: Hotkey?

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var isHovering = false

    public init(hotkey: Binding<Hotkey?>) {
        self._hotkey = hotkey
    }

    public var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(label)
                    .font(TGType.caption)
                    .monospacedDigit()
                    .foregroundStyle(labelColor)
                    .frame(minWidth: 100)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(background)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.12),
                                          lineWidth: isRecording ? 2 : 1)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }

            Button {
                hotkey = nil
                stopRecording()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Clear shortcut")
            .opacity(hotkey == nil ? 0 : 1)
            .disabled(hotkey == nil)
        }
        .onDisappear(perform: stopRecording)
    }

    // MARK: - Appearance

    private var label: String {
        if isRecording { return "Type shortcut…" }
        if let hotkey { return KeyGlyphs.display(hotkey) }
        return "Record"
    }

    private var labelColor: Color {
        if isRecording { return .secondary }
        return hotkey == nil ? .secondary : .primary
    }

    private var background: Color {
        if isRecording { return Color.accentColor.opacity(0.10) }
        return Color.primary.opacity(isHovering ? 0.08 : 0.04)
    }

    // MARK: - Recording

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Swallow everything while recording so the window doesn't act on the keys.
            guard event.type == .keyDown else { return nil }
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)

        // Bare Escape backs out; Delete clears.
        let carbon = KeyGlyphs.carbonModifiers(from: event.modifierFlags)
        if keyCode == UInt32(kVK_Escape), carbon == 0 {
            stopRecording()
            return
        }
        if keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete), carbon == 0 {
            hotkey = nil
            stopRecording()
            return
        }

        // ⇧-only combinations would eat ordinary typing system-wide; keep waiting.
        guard KeyGlyphs.hasRequiredModifier(carbon) else { return }

        hotkey = Hotkey(keyCode: keyCode, modifiers: carbon)
        stopRecording()
    }
}
