// TGOverlay — loads the user's real desktop picture, downsampled, off the main thread.
// We never screenshot the desktop (that would trigger a Screen Recording prompt); we read the
// wallpaper file NSWorkspace hands us and blur it ourselves.

import AppKit
import CoreImage
import ImageIO

public enum WallpaperLoader {

    private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()

    /// The wallpaper file backing a given screen, if the system will tell us.
    @MainActor
    public static func url(for screen: NSScreen) -> URL? {
        NSWorkspace.shared.desktopImageURL(for: screen)
    }

    /// Loads, downsamples and blurs. Returns nil for dynamic wallpapers we can't decode, missing
    /// files, or anything else that goes wrong — callers fall back to a gradient.
    ///
    /// The blur happens here, once, on a Core Image context, rather than as a SwiftUI `.blur()`
    /// on a full-resolution image every time the compositor touches the window.
    public static func load(url: URL, maxPixel: CGFloat = 900, blurRadius: Double = 26) -> NSImage? {
        let key = "\(url.path)#\(Int(maxPixel))"
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let cg = blurred(thumbnail, radius: blurRadius) ?? thumbnail
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        lock.lock()
        cache[key] = image
        lock.unlock()
        return image
    }

    // MARK: - Blur

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private static func blurred(_ image: CGImage, radius: Double) -> CGImage? {
        let source = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        // Clamp first, or the Gaussian pulls transparency in from beyond the edges.
        filter.setValue(source.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        return ciContext.createCGImage(output.cropped(to: source.extent),
                                       from: source.extent,
                                       format: .RGBA8,
                                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}
