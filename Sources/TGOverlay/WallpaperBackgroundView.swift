// TGOverlay — the default break background: your own desktop, gone soft.
// The heavy lifting (downsample + Gaussian) happens once in WallpaperLoader; here we only scale
// past the edges so no border shows, add a whisper of blur to hide the upscale, and darken
// enough for white type to sit comfortably.

import SwiftUI

struct WallpaperBackgroundView: View {
    let url: URL?
    let fallback: AmbientBackdrop

    @State private var image: NSImage?
    @State private var didAttempt = false

    var body: some View {
        ZStack {
            // Note the `if`: leaving the fallback in the tree at opacity 0 would keep its
            // forever-repeating drift animations running for the whole break.
            if image == nil {
                AmbientBackdropView(backdrop: fallback)
            }

            if let image {
                GeometryReader { geo in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(1.08)
                        .clipped()
                }
                .drawingGroup(opaque: true)
                .overlay(Color.black.opacity(0.46))
                .overlay(
                    LinearGradient(colors: [.black.opacity(0.28), .clear, .black.opacity(0.34)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .task { await loadIfNeeded() }
    }

    private func loadIfNeeded() async {
        guard !didAttempt, let url else { return }
        didAttempt = true
        let loaded = await Task.detached(priority: .userInitiated) {
            WallpaperLoader.load(url: url)
        }.value
        guard let loaded else { return }
        withAnimation(OverlayMotion.ease(0.45)) { image = loaded }
    }
}
