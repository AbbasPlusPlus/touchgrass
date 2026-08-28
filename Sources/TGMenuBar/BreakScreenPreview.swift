// TGMenuBar — Settings ▸ Appearance hero preview.
// A small mock of the break screen so the chosen background + the clock/title/subtitle toggles
// can be seen together, without importing TGOverlay (same duplication policy as TGPalette).

import AppKit
import SwiftUI
import TGCore

struct BreakScreenPreview: View {

    let background: BreakBackground
    let showClock: Bool
    let showTitle: Bool
    let showSubtitle: Bool
    let title: String
    let subtitle: String

    private let bone = Color(red: 0.906, green: 0.886, blue: 0.816)

    var body: some View {
        ZStack {
            backgroundLayer
            // A gentle scrim, as on the real break screen, so light type stays legible.
            LinearGradient(colors: [.black.opacity(0.10), .black.opacity(0.28)],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 6) {
                if showClock {
                    Text("0:20")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(bone)
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                }
                if showTitle {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(bone)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                }
                if showSubtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(bone.opacity(0.85))
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                }

                HStack(spacing: 7) {
                    previewPill("Skip", filled: false)
                    previewPill("End break", filled: true)
                }
                .padding(.top, 4)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        switch background {
        case .screenBlur:
            LinearGradient(colors: [.tg(0xF2EEDE), .tg(0xD5CEB6)], startPoint: .top, endPoint: .bottom)
                .overlay(Image(systemName: "circle.lefthalf.filled.inverse")
                    .font(.system(size: 34)).foregroundStyle(Color.tg(0x3D443A, opacity: 0.5)))
                .blur(radius: 3)
        case .wallpaper:
            if let image = Self.desktopImage {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                PresetPalette.gradient([.tg(0x4A5343), .tg(0x7C8570)])
            }
        case .gradient(let preset):
            PresetPalette.gradient(PresetPalette.colors(preset))
        case .animated(let preset):
            ZStack {
                PresetPalette.gradient(PresetPalette.colors(preset))
                Image(systemName: "sparkles").font(.system(size: 20))
                    .foregroundStyle(Color.tg(0xF3F1E2, opacity: 0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(12)
            }
        case .image(let path):
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                PresetPalette.gradient([.tg(0x4A5343), .tg(0x7C8570)])
            }
        }
    }

    private func previewPill(_ label: String, filled: Bool) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(filled ? Color(red: 0.06, green: 0.086, blue: 0.047) : bone)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(filled ? bone : Color.white.opacity(0.14)))
            .overlay(filled ? nil : Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
    }

    private static var desktopImage: NSImage? {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }
}
