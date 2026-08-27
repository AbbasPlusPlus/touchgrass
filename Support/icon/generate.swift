// TouchGrass app icon generator.
//
// Run:  $(brew --prefix swift)/bin/swift Support/icon/generate.swift
//
// Draws the icon procedurally with CoreGraphics (no third-party deps), emits
// Support/icon/AppIcon-1024.png, builds Support/icon/AppIcon.iconset at every
// standard size, and runs `iconutil` to produce Support/AppIcon.icns.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Small vector helpers

struct P {
    var x: CGFloat
    var y: CGFloat
    init(_ x: CGFloat, _ y: CGFloat) { self.x = x; self.y = y }
}

func cubicPoint(_ p0: P, _ p1: P, _ p2: P, _ p3: P, _ t: CGFloat) -> P {
    let mt = 1 - t
    let a = mt * mt * mt, b = 3 * mt * mt * t, c = 3 * mt * t * t, d = t * t * t
    return P(a * p0.x + b * p1.x + c * p2.x + d * p3.x,
             a * p0.y + b * p1.y + c * p2.y + d * p3.y)
}

func cubicTangent(_ p0: P, _ p1: P, _ p2: P, _ p3: P, _ t: CGFloat) -> P {
    let mt = 1 - t
    let a = 3 * mt * mt, b = 6 * mt * t, c = 3 * t * t
    return P(a * (p1.x - p0.x) + b * (p2.x - p1.x) + c * (p3.x - p2.x),
             a * (p1.y - p0.y) + b * (p2.y - p1.y) + c * (p3.y - p2.y))
}

// MARK: - Color helpers

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255
    let g = CGFloat((hex >> 8) & 0xFF) / 255
    let b = CGFloat(hex & 0xFF) / 255
    return CGColor(colorSpace: sRGB, components: [r, g, b, alpha])!
}

func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: sRGB,
               colors: stops.map { $0.0 } as CFArray,
               locations: stops.map { $0.1 })!
}

// MARK: - Squircle (continuous corner, superellipse approximation)

/// Rounded rect whose corners are superellipse arcs (|x|^n + |y|^n = r^n, n = 5),
/// which is a close stand-in for Apple's continuous-curvature corner.
func squirclePath(in rect: CGRect, cornerRadius r: CGFloat, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 40
    let e = 2 / n

    // Corner centers, and the angle sweep for each, walking counter-clockwise
    // from the +x axis of each corner.
    let corners: [(center: CGPoint, start: CGFloat)] = [
        (CGPoint(x: rect.maxX - r, y: rect.maxY - r), 0),                  // top-right
        (CGPoint(x: rect.minX + r, y: rect.maxY - r), .pi / 2),            // top-left
        (CGPoint(x: rect.minX + r, y: rect.minY + r), .pi),                // bottom-left
        (CGPoint(x: rect.maxX - r, y: rect.minY + r), 3 * .pi / 2)         // bottom-right
    ]

    var first = true
    for corner in corners {
        for i in 0...steps {
            let a = corner.start + (.pi / 2) * CGFloat(i) / CGFloat(steps)
            let ca = cos(a), sa = sin(a)
            let x = corner.center.x + r * (ca < 0 ? -1 : 1) * pow(abs(ca), e)
            let y = corner.center.y + r * (sa < 0 ? -1 : 1) * pow(abs(sa), e)
            if first {
                path.move(to: CGPoint(x: x, y: y))
                first = false
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
    }
    path.closeSubpath()
    return path
}

// MARK: - Grass blade

struct Blade {
    var base: P            // normalized (0...1) inside the icon body, y up
    var c1: P
    var c2: P
    var tip: P
    var width: CGFloat     // max thickness, normalized to body size
    var tipTaper: CGFloat  // higher = longer, sharper point
    var baseTaper: CGFloat // higher = the blade swells further up from the base
}

/// Outline of a tapered blade: walk the spine, offset along the normal by a
/// width profile that swells just above the base and comes to a point at the tip.
func bladePath(_ b: Blade, origin: CGPoint, scale s: CGFloat) -> CGPath {
    let samples = 220
    let pt = { (n: P) -> CGPoint in CGPoint(x: origin.x + n.x * s, y: origin.y + n.y * s) }

    var left: [CGPoint] = []
    var right: [CGPoint] = []
    left.reserveCapacity(samples + 1)
    right.reserveCapacity(samples + 1)

    for i in 0...samples {
        let t = CGFloat(i) / CGFloat(samples)
        let p = cubicPoint(b.base, b.c1, b.c2, b.tip, t)
        var d = cubicTangent(b.base, b.c1, b.c2, b.tip, t)
        let len = max(sqrt(d.x * d.x + d.y * d.y), 1e-6)
        d = P(d.x / len, d.y / len)
        let nrm = P(-d.y, d.x)

        // Leaf profile: pointed where it leaves the ground, widest around a
        // third of the way up, tapering to a fine point. Normalised so the
        // widest part is exactly `width`.
        let a = b.baseTaper, c = b.tipTaper
        let peak = a / (a + c)
        let norm = pow(peak, a) * pow(1 - peak, c)
        let w = b.width * 0.5 * pow(max(0, t), a) * pow(max(0, 1 - t), c) / norm

        left.append(pt(P(p.x + nrm.x * w, p.y + nrm.y * w)))
        right.append(pt(P(p.x - nrm.x * w, p.y - nrm.y * w)))
    }

    let path = CGMutablePath()
    path.move(to: left[0])
    path.addLines(between: Array(left.dropFirst()))
    path.addLines(between: right.reversed())
    path.closeSubpath()
    return path
}

// MARK: - Composition

let blades: [Blade] = [
    // Two low blades in a deeper green that splay out past the main pair, so
    // the tuft layers instead of reading as flat cut-outs.
    Blade(base: P(0.482, 0.090), c1: P(0.424, 0.196), c2: P(0.322, 0.318),
          tip: P(0.222, 0.418), width: 0.094, tipTaper: 0.80, baseTaper: 0.46),
    Blade(base: P(0.520, 0.090), c1: P(0.582, 0.190), c2: P(0.686, 0.302),
          tip: P(0.782, 0.400), width: 0.090, tipTaper: 0.80, baseTaper: 0.46),
    // Left blade, sweeping out and over.
    Blade(base: P(0.460, 0.086), c1: P(0.412, 0.300), c2: P(0.296, 0.478),
          tip: P(0.196, 0.618), width: 0.126, tipTaper: 0.78, baseTaper: 0.42),
    // Right blade.
    Blade(base: P(0.546, 0.086), c1: P(0.606, 0.318), c2: P(0.712, 0.502),
          tip: P(0.806, 0.652), width: 0.128, tipTaper: 0.78, baseTaper: 0.42),
    // Centre blade — tallest, reads first at 16 px.
    Blade(base: P(0.502, 0.078), c1: P(0.462, 0.362), c2: P(0.498, 0.668),
          tip: P(0.542, 0.878), width: 0.146, tipTaper: 0.74, baseTaper: 0.40)
]

func drawIcon(into ctx: CGContext, size S: CGFloat) {
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // Standard macOS icon grid: 824/1024 body centred in the canvas.
    let inset = S * (100.0 / 1024.0)
    let body = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
    let radius = body.width * 0.225
    let shape = squirclePath(in: body, cornerRadius: radius)

    // ---- Background: dusk sky falling into lawn -------------------------
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    ctx.drawLinearGradient(
        gradient([
            (rgb(0x489C57), 0.00),   // warm grass green (bottom)
            (rgb(0x2E7A53), 0.24),
            (rgb(0x1E6355), 0.46),
            (rgb(0x1A4757), 0.68),
            (rgb(0x1C3352), 0.88),
            (rgb(0x1F2D4E), 1.00)    // deep dusk indigo (top)
        ]),
        start: CGPoint(x: body.midX, y: body.minY),
        end: CGPoint(x: body.midX, y: body.maxY),
        options: []
    )

    // Soft halo behind the tuft so the blades feel lit.
    ctx.drawRadialGradient(
        gradient([(rgb(0xC8FFD8, 0.16), 0.0), (rgb(0xC8FFD8, 0.0), 1.0)]),
        startCenter: CGPoint(x: body.midX, y: body.minY + body.height * 0.36),
        startRadius: 0,
        endCenter: CGPoint(x: body.midX, y: body.minY + body.height * 0.36),
        endRadius: body.width * 0.52,
        options: []
    )

    // Vignette: gently darken the outer corners.
    ctx.drawRadialGradient(
        gradient([(rgb(0x000000, 0.0), 0.55), (rgb(0x001018, 0.20), 1.0)]),
        startCenter: CGPoint(x: body.midX, y: body.midY),
        startRadius: 0,
        endCenter: CGPoint(x: body.midX, y: body.midY),
        endRadius: body.width * 0.78,
        options: [.drawsAfterEndLocation]
    )

    // Top-edge sheen.
    ctx.drawLinearGradient(
        gradient([(rgb(0xFFFFFF, 0.0), 0.0), (rgb(0xEAF6FF, 0.13), 1.0)]),
        start: CGPoint(x: body.midX, y: body.maxY - body.height * 0.30),
        end: CGPoint(x: body.midX, y: body.maxY),
        options: []
    )

    // Fine grain, large sizes only.
    if S >= 128 { drawGrain(ctx, rect: body, alpha: 0.030) }
    ctx.restoreGState()

    // ---- Grass -----------------------------------------------------------
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // Soft pool of shade where the blades leave the ground.
    if S >= 40 {
    ctx.saveGState()
    let groundC = CGPoint(x: body.minX + body.width * 0.503, y: body.minY + body.height * 0.098)
    ctx.translateBy(x: groundC.x, y: groundC.y)
    ctx.scaleBy(x: 1, y: 0.34)
    ctx.drawRadialGradient(
        gradient([(rgb(0x06180F, 0.30), 0.0), (rgb(0x06180F, 0.18), 0.45), (rgb(0x06180F, 0.0), 1.0)]),
        startCenter: .zero, startRadius: 0,
        endCenter: .zero, endRadius: body.width * 0.20,
        options: []
    )
    ctx.restoreGState()
    }

    // Below ~40 px the two low blades turn to mush, so the small variants get
    // the three main blades only, drawn slightly heavier.
    let small = S < 40
    let visible = small ? Array(blades.dropFirst(2)) : blades
    let fatten: CGFloat = small ? 1.16 : 1.0

    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.012),
                  blur: S * (small ? 0.05 : 0.032),
                  color: rgb(0x03140C, small ? 0.20 : 0.34))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)

    for (i, blade) in visible.enumerated() {
        var blade = blade
        blade.width *= fatten
        let path = bladePath(blade, origin: body.origin, scale: body.width)
        let box = path.boundingBox
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let stops: [(CGColor, CGFloat)] = (!small && i < 2)
            ? [(rgb(0x358560), 0.0), (rgb(0x5FB27C), 0.55), (rgb(0x8FD09C), 1.0)]   // behind
            : [(rgb(0x66C98A), 0.0), (rgb(0xAFEAB6), 0.50), (rgb(0xF2FFEE), 1.0)]
        ctx.drawLinearGradient(gradient(stops),
                               start: CGPoint(x: box.midX, y: box.minY),
                               end: CGPoint(x: box.midX, y: box.maxY),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // ---- Inner rim light along the top edge ------------------------------
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.addPath(shape)
    ctx.setLineWidth(max(0.75, S * 0.0045) * 2)   // half of it is clipped away
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(rgb(0xFFFFFF, 0.0), 0.0), (rgb(0xFFFFFF, 0.0), 0.42), (rgb(0xFFFFFF, 0.10), 0.72), (rgb(0xFFFFFF, 0.30), 1.0)]),
        start: CGPoint(x: body.midX, y: body.minY),
        end: CGPoint(x: body.midX, y: body.maxY),
        options: []
    )
    ctx.restoreGState()
}

/// Deterministic low-amplitude grain so large renders don't look plasticky.
func drawGrain(_ ctx: CGContext, rect: CGRect, alpha: CGFloat) {
    let n = 220
    var seed: UInt64 = 0x9E3779B97F4A7C15
    func rand() -> CGFloat {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return CGFloat(seed % 10_000) / 10_000
    }
    var bytes = [UInt8](repeating: 0, count: n * n * 4)
    for i in 0..<(n * n) {
        let v = UInt8(120 + Int(rand() * 70))
        let a = UInt8(alpha * 255)
        bytes[i * 4 + 0] = UInt8(CGFloat(v) * CGFloat(a) / 255)
        bytes[i * 4 + 1] = bytes[i * 4 + 0]
        bytes[i * 4 + 2] = bytes[i * 4 + 0]
        bytes[i * 4 + 3] = a
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
          let img = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: n * 4, space: sRGB,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false,
                            intent: .defaultIntent)
    else { return }
    ctx.saveGState()
    ctx.setBlendMode(.overlay)
    ctx.draw(img, in: rect, byTiling: true)
    ctx.restoreGState()
}

// MARK: - Rendering / output

func render(size: Int) -> CGImage {
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("could not create \(size)px context") }
    drawIcon(into: ctx, size: CGFloat(size))
    guard let img = ctx.makeImage() else { fatalError("could not snapshot \(size)px context") }
    return img
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("could not open \(url.path) for writing")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
}

let fm = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0],
                    relativeTo: URL(fileURLWithPath: fm.currentDirectoryPath)).standardizedFileURL
let iconDir = scriptURL.deletingLastPathComponent()               // Support/icon
let supportDir = iconDir.deletingLastPathComponent()              // Support
let iconsetDir = iconDir.appendingPathComponent("AppIcon.iconset")
let icnsURL = supportDir.appendingPathComponent("AppIcon.icns")

// Every size is drawn natively rather than downscaled, so the blades stay crisp
// at 16 px.
let master = render(size: 1024)
writePNG(master, to: iconDir.appendingPathComponent("AppIcon-1024.png"))

try? fm.removeItem(at: iconsetDir)
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let variants: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for v in variants {
    let img = v.px == 1024 ? master : render(size: v.px)
    writePNG(img, to: iconsetDir.appendingPathComponent("\(v.name).png"))
    print("  rendered \(v.name).png (\(v.px)px)")
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed (\(iconutil.terminationStatus))\n".utf8))
    exit(1)
}

print("✓ \(iconDir.appendingPathComponent("AppIcon-1024.png").path)")
print("✓ \(icnsURL.path)")
