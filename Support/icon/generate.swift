// TouchGrass app icon generator.
//
// Run:  $(brew --prefix swift)/bin/swift Support/icon/generate.swift
//
// Draws the approved mark (Support/logo/touchgrass-mark.svg — five flat blades clipped to a
// disc) on a paper squircle, emits Support/icon/AppIcon-1024.png, builds
// Support/icon/AppIcon.iconset at every standard size, and runs `iconutil` to produce
// Support/AppIcon.icns.
//
// The path data below is the SVG's, verbatim, in its 512×512 viewBox. `TGMenuBar` and
// `TGOverlay` each carry a copy (`LogoMarkGeometry`) because a standalone script can't import
// them. If one changes, change all three.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Colour helpers

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

// MARK: - The mark

enum Mark {
    static let viewBox: CGFloat = 512
    static let discCentre = CGPoint(x: 262, y: 268)
    static let discRadius: CGFloat = 192

    enum Command {
        case move(CGFloat, CGFloat)
        case line(CGFloat, CGFloat)
        case curve(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
    }

    struct Blade {
        let hex: UInt32
        /// The two thin slits, which turn to mush below ~26 px.
        let isSliver: Bool
        let commands: [Command]
    }

    static let blades: [Blade] = [
        // 1 · big light crescent along the left rim
        Blade(hex: 0xA6C84D, isSliver: false, commands: [
            .move(348, 82),
            .curve(220, 96, 72, 180, 72, 300),
            .curve(72, 400, 180, 462, 285, 462),
            .curve(205, 428, 163, 345, 180, 258),
            .curve(197, 170, 270, 112, 348, 82),
        ]),
        // 2 · second blade, fat, base flows to bottom
        Blade(hex: 0x78AF43, isSliver: false, commands: [
            .move(408, 150),
            .curve(320, 180, 238, 252, 213, 342),
            .curve(202, 400, 210, 442, 228, 462),
            .line(372, 462),
            .curve(320, 380, 330, 268, 408, 150),
        ]),
        // 3 · third blade, overlapping blade 2's base
        Blade(hex: 0x4F8D3C, isSliver: true, commands: [
            .move(452, 226),
            .curve(368, 252, 296, 314, 268, 384),
            .curve(254, 424, 258, 452, 272, 462),
            .line(400, 462),
            .curve(370, 390, 392, 302, 452, 226),
        ]),
        // 4 · dark bottom mass, spanning the whole base
        Blade(hex: 0x27521F, isSliver: false, commands: [
            .move(462, 302),
            .curve(372, 314, 296, 356, 258, 408),
            .curve(236, 430, 222, 448, 214, 462),
            .line(470, 462),
            .line(470, 302),
            .curve(468, 302, 465, 302, 462, 302),
        ]),
        // 5 · light leaf over the dark mass, belly on the rim
        Blade(hex: 0x93C04C, isSliver: true, commands: [
            .move(288, 456),
            .curve(314, 384, 376, 342, 452, 332),
            .curve(452, 392, 424, 434, 382, 452),
            .curve(350, 464, 314, 464, 288, 456),
        ]),
    ]

    /// Maps the *disc* (not the viewBox) into `rect`, in CoreGraphics' bottom-left origin.
    /// Returns scale and offsets for `point(x, y) = (dx + x·s, dy + (viewBox − y)·s)`.
    static func mapping(discIn rect: CGRect) -> (s: CGFloat, dx: CGFloat, dy: CGFloat) {
        let s = rect.width / (discRadius * 2)
        let minX = discCentre.x - discRadius
        let minYFlipped = viewBox - (discCentre.y + discRadius)
        return (s, rect.minX - minX * s, rect.minY - minYFlipped * s)
    }

    static func path(_ commands: [Command], discIn rect: CGRect) -> CGPath {
        let (s, dx, dy) = mapping(discIn: rect)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + (viewBox - y) * s)
        }
        let path = CGMutablePath()
        for command in commands {
            switch command {
            case .move(let x, let y): path.move(to: point(x, y))
            case .line(let x, let y): path.addLine(to: point(x, y))
            case .curve(let a, let b, let c, let d, let x, let y):
                path.addCurve(to: point(x, y), control1: point(a, b), control2: point(c, d))
            }
        }
        path.closeSubpath()
        return path
    }

    /// Draws the mark so its disc exactly fills `rect`.
    static func draw(into ctx: CGContext, discIn rect: CGRect, dropSlivers: Bool) {
        ctx.saveGState()
        ctx.addEllipse(in: rect)
        ctx.clip()
        for blade in blades {
            let hex = (dropSlivers && blade.isSliver) ? 0x27521F : blade.hex
            ctx.addPath(path(blade.commands, discIn: rect))
            ctx.setFillColor(rgb(UInt32(hex)))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }
}

// MARK: - Composition

/// Paper (#F2EEDE), a whisper of grain, and the mark with ~12 % of the body left as margin.
func drawIcon(into ctx: CGContext, size S: CGFloat) {
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // Standard macOS icon grid: 824/1024 body centred in the canvas.
    let inset = S * (100.0 / 1024.0)
    let body = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
    let radius = body.width * 0.225
    let shape = squirclePath(in: body, cornerRadius: radius)

    // ---- Paper ------------------------------------------------------------
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // Not a flat fill: a barely-there vertical lift keeps 1024 px of beige from looking dead.
    ctx.drawLinearGradient(
        gradient([(rgb(0xEDE8D6), 0.0), (rgb(0xF2EEDE), 0.45), (rgb(0xFAF7EC), 1.0)]),
        start: CGPoint(x: body.midX, y: body.minY),
        end: CGPoint(x: body.midX, y: body.maxY),
        options: []
    )

    if S >= 128 { drawGrain(ctx, rect: body, alpha: 0.045) }

    // A soft warm shade under where the mark sits, so the disc has something to sit *on*.
    ctx.drawRadialGradient(
        gradient([(rgb(0x8A8460, 0.10), 0.0), (rgb(0x8A8460, 0.0), 1.0)]),
        startCenter: CGPoint(x: body.midX, y: body.minY + body.height * 0.40),
        startRadius: 0,
        endCenter: CGPoint(x: body.midX, y: body.minY + body.height * 0.40),
        endRadius: body.width * 0.56,
        options: []
    )
    ctx.restoreGState()

    // ---- The mark ---------------------------------------------------------
    // 12 % margin on each side leaves the disc 76 % of the body. Below 64 px there is no room
    // to spend an eighth of the tile on air, so the margin halves and the mark fills it.
    let margin = body.width * (S >= 64 ? 0.12 : 0.06)
    let disc = CGRect(x: body.minX + margin, y: body.minY + margin,
                      width: body.width - margin * 2, height: body.height - margin * 2)

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    if S >= 64 {
        ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.010),
                      blur: S * 0.030,
                      color: rgb(0x3A3A22, 0.22))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    }
    // Below ~26 px of *disc* the two thin slits are sub-pixel and only dirty the silhouette.
    Mark.draw(into: ctx, discIn: disc, dropSlivers: disc.width < 26)
    if S >= 64 { ctx.endTransparencyLayer() }
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
        gradient([(rgb(0x8A8460, 0.14), 0.0), (rgb(0xFFFFFF, 0.0), 0.45), (rgb(0xFFFFFF, 0.28), 1.0)]),
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

// Every size is drawn natively rather than downscaled, so the mark stays crisp at 16 px.
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
