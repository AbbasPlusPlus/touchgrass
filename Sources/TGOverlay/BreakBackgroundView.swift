// TGOverlay — resolves a `BreakBackground` setting into an actual full-screen backdrop.

import SwiftUI
import TGCore

struct BreakBackgroundView: View {
    let background: BreakBackground
    /// The wallpaper of the specific screen this instance is drawn on.
    let wallpaperURL: URL?

    /// What a wallpaper falls back to when the file can't be read (dynamic wallpapers, missing file).
    private static let fallback: AmbientBackdrop = .gradient(.dusk)

    var body: some View {
        switch background {
        case .wallpaper:
            WallpaperBackgroundView(url: wallpaperURL, fallback: Self.fallback)
        case .gradient(let preset):
            AmbientBackdropView(backdrop: .gradient(preset))
        case .animated(let preset):
            AmbientBackdropView(backdrop: .animated(preset))
        case .image(let path):
            WallpaperBackgroundView(url: URL(fileURLWithPath: path), fallback: Self.fallback)
        }
    }
}
