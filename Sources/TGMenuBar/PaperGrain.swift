// TGMenuBar — the paper texture laid over matte surfaces.
import AppKit
import SwiftUI

/// A tiled speck of noise at a few percent, which is the whole difference between "warm paper"
/// and "flat beige rectangle".
///
/// The tile is generated once, deterministically, and cached: 128 px of half-white/half-black
/// specks. Mixing both polarities means the same tile works on light paper (where the dark
/// specks read) and on ink paper (where the light ones do), so there is nothing to swap when
/// the system flips appearance.
struct PaperGrain: View {

    /// Overall strength. DESIGN.md asks for ~4%.
    var opacity: Double = 0.04

    var body: some View {
        Image(nsImage: Self.tile)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - The tile

    static let tile: NSImage = makeTile(side: 128)

    private static func makeTile(side: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side))
        guard let cg = PaperGrain.noise(side: side) else { return image }
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }

    /// Deterministic xorshift noise so two runs produce byte-identical texture.
    static func noise(side: Int) -> CGImage? {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> UInt32 {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return UInt32(truncatingIfNeeded: seed)
        }

        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for i in 0..<(side * side) {
            let r = next()
            // Only about a third of the pixels carry any ink at all; a solid field of noise
            // reads as a screen-door rather than as paper.
            let carries = r & 0x3 != 0
            guard carries else { continue }
            let white = (r >> 8) & 1 == 0
            let alpha = UInt8(90 + Int((r >> 16) % 110))     // premultiplied below
            let level: UInt8 = white ? 255 : 0
            let premul = UInt8(Int(level) * Int(alpha) / 255)
            bytes[i * 4 + 0] = premul
            bytes[i * 4 + 1] = premul
            bytes[i * 4 + 2] = premul
            bytes[i * 4 + 3] = alpha
        }

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData)
        else { return nil }
        return CGImage(width: side, height: side,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}

// MARK: - Convenience

extension View {
    /// Lays paper grain over this view, clipped to `shape`.
    func paperGrain<S: Shape>(_ shape: S, opacity: Double = 0.04) -> some View {
        overlay(PaperGrain(opacity: opacity).clipShape(shape))
    }

    /// Lays paper grain over this view, edge to edge.
    func paperGrain(opacity: Double = 0.04) -> some View {
        overlay(PaperGrain(opacity: opacity))
    }
}
