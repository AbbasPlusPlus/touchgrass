// TGMenuBar — choosing what the break screen looks like.
import AppKit
import SwiftUI
import TGCore
import UniformTypeIdentifiers

/// Wallpaper, six gradients, four animated scenes, or an image of the user's own.
struct BackgroundPicker: View {

    @Binding var background: BreakBackground

    private let columns = [GridItem(.adaptive(minimum: 78, maximum: 88), spacing: 10, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            group("Your desktop") {
                BackgroundTile(caption: "Screen blur", isSelected: background == .screenBlur) {
                    background = .screenBlur
                } content: {
                    AnyView(
                        LinearGradient(colors: [.tg(0xF2EEDE), .tg(0xD5CEB6)],
                                       startPoint: .top, endPoint: .bottom)
                            .overlay(Image(systemName: "circle.lefthalf.filled.inverse")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.tg(0x3D443A, opacity: 0.55)))
                            .blur(radius: 1.5)
                    )
                }
                BackgroundTile(caption: "Wallpaper", isSelected: background == .wallpaper) {
                    background = .wallpaper
                } content: {
                    AnyView(wallpaperPreview)
                }
            }

            group("Gradients") {
                ForEach(GradientPreset.allCases, id: \.self) { preset in
                    BackgroundTile(
                        caption: PresetPalette.title(preset),
                        isSelected: background == .gradient(preset),
                        action: { background = .gradient(preset) },
                        content: { AnyView(PresetPalette.gradient(PresetPalette.colors(preset))) }
                    )
                }
            }

            group("Animated") {
                ForEach(AnimatedPreset.allCases, id: \.self) { preset in
                    BackgroundTile(
                        caption: PresetPalette.title(preset),
                        isSelected: background == .animated(preset),
                        action: { background = .animated(preset) },
                        content: { AnyView(animatedPreview(preset)) }
                    )
                }
            }

            group("Custom") {
                BackgroundTile(
                    caption: customCaption,
                    isSelected: isCustomImage,
                    action: chooseImage,
                    content: { AnyView(customPreview) }
                )
            }
        }
    }

    // MARK: - Layout

    private func group<Content: View>(_ header: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(header)
                .font(TGType.caption)
                .foregroundStyle(TGPalette.ink2)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                content()
            }
        }
    }

    // MARK: - Previews

    /// The user's real desktop picture, so the "Wallpaper" tile shows what they'd actually get.
    private var wallpaperPreview: some View {
        Group {
            if let image = Self.desktopImage {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    PresetPalette.gradient([.tg(0x4A5343), .tg(0x7C8570)])
                    Image(systemName: "photo.on.rectangle.angled")
                        .foregroundStyle(Color.tg(0xF3F1E2, opacity: 0.85))
                }
            }
        }
    }

    /// Animated scenes get a hint of motion: a couple of drifting strokes over the base gradient.
    private func animatedPreview(_ preset: AnimatedPreset) -> some View {
        ZStack {
            PresetPalette.gradient(PresetPalette.colors(preset))
            Image(systemName: "sparkles")
                .font(.system(size: 13))
                .foregroundStyle(Color.tg(0xF3F1E2, opacity: 0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(5)
        }
    }

    private var customPreview: some View {
        Group {
            if case .image(let path) = background, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    TGPalette.paper2
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(TGPalette.ink2)
                }
            }
        }
    }

    private var isCustomImage: Bool {
        if case .image = background { return true }
        return false
    }

    private var customCaption: String {
        if case .image(let path) = background {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return "Custom…"
    }

    // MARK: - Actions

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose a background image"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        background = .image(path: url.path)
    }

    private static var desktopImage: NSImage? {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }
}
