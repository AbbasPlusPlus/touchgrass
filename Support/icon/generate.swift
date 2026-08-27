// TouchGrass app icon generator.
//
// Run:  $(brew --prefix swift)/bin/swift Support/icon/generate.swift
//
// Draws the approved mark on a paper squircle, emits Support/icon/AppIcon-1024.png, builds
// Support/icon/AppIcon.iconset at every standard size, and runs `iconutil` to produce
// Support/AppIcon.icns.
//
// The mark is read straight out of Support/logo/touchgrass-mark.svg at run time, so the icon
// can never drift from the file. `SVGPathParser` below is a verbatim copy of the one in
// TGMenuBar / TGOverlay (a standalone script can't import them) — if one changes, change all.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Locations

let fm = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0],
                    relativeTo: URL(fileURLWithPath: fm.currentDirectoryPath)).standardizedFileURL
let iconDir = scriptURL.deletingLastPathComponent()               // Support/icon
let supportDir = iconDir.deletingLastPathComponent()              // Support
let iconsetDir = iconDir.appendingPathComponent("AppIcon.iconset")
let icnsURL = supportDir.appendingPathComponent("AppIcon.icns")
let svgURL = supportDir.appendingPathComponent("logo/touchgrass-mark.svg")

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

// MARK: - SVG path data

/// Turns an SVG path's `d` attribute into a `CGPath`, in the SVG's own coordinate space
/// (y down, origin top-left). Mapping into a destination rect is `LogoMarkGeometry`'s job.
///
/// Covers everything the designer's export uses and a little more: `M m L l H h V v C c
/// S s Q q T t Z z`, repeated implicit commands, and the shorthand number soup real
/// exporters emit (`.5.5` is two numbers, `1-2` is two numbers, exponents are numbers).
/// Elliptical arcs (`A a`) are *not* supported — `parse` returns nil rather than quietly
/// dropping them, so a future SVG that uses them fails loudly at generation time.
///
/// Verbatim copies live in `TGMenuBar` and `TGOverlay` (a standalone script can't import
/// them). If one changes, change all three.
enum SVGPathParser {

    // MARK: - Public

    /// - Returns: nil if `d` contains an unsupported command or runs out of arguments.
    static func parse(_ d: String) -> CGPath? {
        var scanner = Scanner(d)
        let path = CGMutablePath()

        var current = CGPoint.zero          // current point
        var start = CGPoint.zero            // start of the current subpath, for Z
        var lastCubicControl: CGPoint?      // second control of the previous C/S, for S
        var lastQuadControl: CGPoint?       // control of the previous Q/T, for T
        var command: UInt8 = 0

        while true {
            scanner.skipSeparators()
            guard let next = scanner.peek() else { break }

            var explicit = false
            if isCommand(next) {
                command = next
                explicit = true
                scanner.advance()
            } else if command == 0 {
                return nil                  // numbers before any command
            } else if command == UInt8(ascii: "M") || command == UInt8(ascii: "m") {
                // A repeated moveto's extra coordinate pairs are linetos, per the spec.
                command = command == UInt8(ascii: "M") ? UInt8(ascii: "L") : UInt8(ascii: "l")
            }

            let relative = command >= UInt8(ascii: "a")     // lowercase == relative
            func origin() -> CGPoint { relative ? current : .zero }
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: origin().x + x, y: origin().y + y)
            }

            switch command | 0x20 {         // lowercase the letter
            case UInt8(ascii: "z"):
                // Z takes no arguments, so an "implicit repeat" of it would consume nothing
                // and spin forever. Malformed input; bail.
                guard explicit else { return nil }
                path.closeSubpath()
                current = start
                lastCubicControl = nil
                lastQuadControl = nil

            case UInt8(ascii: "m"):
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                current = point(x, y)
                start = current
                path.move(to: current)
                lastCubicControl = nil
                lastQuadControl = nil

            case UInt8(ascii: "l"):
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                current = point(x, y)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadControl = nil

            case UInt8(ascii: "h"):
                guard let x = scanner.number() else { return nil }
                current = CGPoint(x: origin().x + x, y: current.y)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadControl = nil

            case UInt8(ascii: "v"):
                guard let y = scanner.number() else { return nil }
                current = CGPoint(x: current.x, y: origin().y + y)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadControl = nil

            case UInt8(ascii: "c"):
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return nil }
                let c1 = point(x1, y1), c2 = point(x2, y2)
                current = point(x, y)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastCubicControl = c2
                lastQuadControl = nil

            case UInt8(ascii: "s"):
                guard let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return nil }
                let c1 = reflect(lastCubicControl, about: current)
                let c2 = point(x2, y2)
                current = point(x, y)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastCubicControl = c2
                lastQuadControl = nil

            case UInt8(ascii: "q"):
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return nil }
                let c = point(x1, y1)
                current = point(x, y)
                path.addQuadCurve(to: current, control: c)
                lastQuadControl = c
                lastCubicControl = nil

            case UInt8(ascii: "t"):
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                let c = reflect(lastQuadControl, about: current)
                current = point(x, y)
                path.addQuadCurve(to: current, control: c)
                lastQuadControl = c
                lastCubicControl = nil

            default:
                return nil                  // A/a and anything else
            }
        }

        return path.isEmpty ? nil : path.copy()
    }

    // MARK: - Helpers

    /// The smooth-curve shorthand's implied control point: the previous one mirrored through
    /// the current point, or the current point itself when there was no previous curve.
    private static func reflect(_ control: CGPoint?, about point: CGPoint) -> CGPoint {
        guard let control else { return point }
        return CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
    }

    private static func isCommand(_ byte: UInt8) -> Bool {
        switch byte | 0x20 {
        case UInt8(ascii: "m"), UInt8(ascii: "l"), UInt8(ascii: "h"), UInt8(ascii: "v"),
             UInt8(ascii: "c"), UInt8(ascii: "s"), UInt8(ascii: "q"), UInt8(ascii: "t"),
             UInt8(ascii: "a"), UInt8(ascii: "z"):
            return true
        default:
            return false
        }
    }

    // MARK: - Scanner

    /// A byte cursor over the `d` string. SVG path data is ASCII, so bytes are enough.
    private struct Scanner {
        private let bytes: [UInt8]
        private var index = 0

        init(_ string: String) { bytes = Array(string.utf8) }

        func peek() -> UInt8? { index < bytes.count ? bytes[index] : nil }

        mutating func advance() { index += 1 }

        /// Whitespace and commas both separate numbers, in any mixture.
        mutating func skipSeparators() {
            while index < bytes.count {
                switch bytes[index] {
                case 0x20, 0x09, 0x0A, 0x0D, 0x0C, UInt8(ascii: ","):
                    index += 1
                default:
                    return
                }
            }
        }

        /// One number, with the exporter shorthands: a leading `-`/`+` starts a new number
        /// without a separator, and a second `.` does too (`.5.5` is 0.5 then 0.5).
        mutating func number() -> CGFloat? {
            skipSeparators()
            let begin = index
            var sawDigit = false
            var sawDot = false

            if index < bytes.count, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") {
                index += 1
            }
            loop: while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: "0")...UInt8(ascii: "9"):
                    sawDigit = true
                    index += 1
                case UInt8(ascii: "."):
                    if sawDot { break loop }
                    sawDot = true
                    index += 1
                default:
                    break loop
                }
            }
            guard sawDigit else {
                index = begin
                return nil
            }
            // Exponent, only when it is actually followed by digits.
            if index < bytes.count, bytes[index] | 0x20 == UInt8(ascii: "e") {
                var lookahead = index + 1
                if lookahead < bytes.count,
                   bytes[lookahead] == UInt8(ascii: "-") || bytes[lookahead] == UInt8(ascii: "+") {
                    lookahead += 1
                }
                var digits = lookahead
                while digits < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[digits]) {
                    digits += 1
                }
                if digits > lookahead { index = digits }
            }

            guard let text = String(bytes: bytes[begin..<index], encoding: .utf8),
                  let value = Double(text) else { return nil }
            return CGFloat(value)
        }
    }
}

// MARK: - The mark

/// Reads every `<path>` out of the designer SVG, in document (= paint) order.
///
/// The viewBox is deliberately ignored: the icon fits the artwork's own bounds to the tile,
/// not the box the designer happened to export it in.
final class MarkSVGReader: NSObject, XMLParserDelegate {
    var shapes: [(d: String, colour: CGColor)] = []

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        guard element == "path", let d = attributes["d"] else { return }
        let fill = attributes["fill"] ?? "#000000"
        guard fill.lowercased() != "none", let colour = hexColour(fill) else { return }
        shapes.append((d, colour))
    }

    /// `#rgb` / `#rrggbb`.
    private func hexColour(_ text: String) -> CGColor? {
        var digits = text.trimmingCharacters(in: .whitespaces)
        digits.removeFirst(digits.hasPrefix("#") ? 1 : 0)
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return rgb(value)
    }
}

enum Mark {
    struct Shape {
        let path: CGPath
        let colour: CGColor
    }

    static let shapes: [Shape] = {
        let reader = MarkSVGReader()
        guard let data = try? Data(contentsOf: svgURL) else {
            fatalError("could not read \(svgURL.path)")
        }
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else { fatalError("could not parse \(svgURL.lastPathComponent)") }

        let parsed = reader.shapes.map { shape -> Shape in
            guard let path = SVGPathParser.parse(shape.d) else {
                fatalError("unsupported path data in \(svgURL.lastPathComponent): \(shape.d)")
            }
            return Shape(path: path, colour: shape.colour)
        }
        guard !parsed.isEmpty else { fatalError("no filled paths in \(svgURL.lastPathComponent)") }
        return parsed
    }()

    /// The artwork's true extent, which is a little smaller than the viewBox.
    static let bounds: CGRect = shapes.reduce(.null) { $0.union($1.path.boundingBoxOfPath) }

    /// Draws the mark so its artwork exactly fills `rect`, in CoreGraphics' bottom-left origin.
    static func draw(into ctx: CGContext, in rect: CGRect) {
        let scale = min(rect.width, rect.height) / max(bounds.width, bounds.height)
        var matrix = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale,
                                       tx: rect.midX - bounds.midX * scale,
                                       ty: rect.midY + bounds.midY * scale)
        ctx.saveGState()
        ctx.setShouldAntialias(true)
        for shape in shapes {
            guard let path = shape.path.copy(using: &matrix) else { continue }
            ctx.addPath(path)
            ctx.setFillColor(shape.colour)
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
    // 12 % margin on each side leaves the mark 76 % of the body. Below 64 px it grows a little
    // to buy back some pixels — but not to 6 %, which puts the blade tips into the squircle's
    // corners and leaves the tile reading as a green square instead of a disc of grass.
    //
    // Every one of the 46 paths is drawn at every size. Rendering 16 px and 32 px against a
    // version with the 33 hairline seam-fillers dropped differs by at most 2/255 on 16 of the
    // 16 px tile's subpixels, so there is nothing to gain by simplifying.
    let margin = body.width * (S >= 64 ? 0.12 : 0.10)
    let markRect = CGRect(x: body.minX + margin, y: body.minY + margin,
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
    Mark.draw(into: ctx, in: markRect)
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
