// TGOverlay — ambient backgrounds as Core Animation layer trees.
//
// Why not SwiftUI? Measured on a 3024×1964 display: the same art built from SwiftUI shapes and
// gradients costs 8–35% CPU, because every animated frame re-rasterizes a full-screen display
// list on the main thread. Expressed as CALayers with CABasicAnimation, the interpolation and
// compositing happen in the render server and this process stays near zero.
//
// Everything here is built once per screen, at panel construction. Nothing recomputes per frame.

import AppKit
import CoreImage
import TGCore

enum AmbientBackdropBuilder {

    /// Builds the full layer stack for a backdrop, sized to `size`.
    /// `animated == false` (Reduce Motion) builds the identical art, frozen at its first pose.
    static func layers(for backdrop: AmbientBackdrop, size: CGSize, animated: Bool) -> [CALayer] {
        switch backdrop {
        case .gradient(let preset):
            return gradient(GradientPalette.palette(for: preset), size: size, animated: animated)
        case .animated(.slipstream):
            return slipstream(size: size, animated: animated)
        case .animated(.fireflies):
            return fireflies(size: size, animated: animated)
        case .animated(.topography):
            return topography(size: size, animated: animated)
        case .animated(.aurora):
            return aurora(size: size, animated: animated)
        }
    }

    // MARK: - Gradient

    private static func gradient(_ palette: GradientPalette, size: CGSize, animated: Bool) -> [CALayer] {
        let w = size.width, h = size.height
        var layers: [CALayer] = [axial(palette.baseCGColors, frame: CGRect(origin: .zero, size: size))]

        let diameter = max(w, h) * 0.95
        let a = radial(.tg(palette.bloomA.hex, opacity: palette.bloomA.alpha), diameter: diameter)
        drift(a, size: size,
              from: CGPoint(x: 0.70, y: 0.36), to: CGPoint(x: 0.32, y: 0.68),
              scale: (0.92, 1.10), duration: 34, animated: animated)
        layers.append(a)

        let b = radial(.tg(palette.bloomB.hex, opacity: palette.bloomB.alpha), diameter: diameter * 0.82)
        drift(b, size: size,
              from: CGPoint(x: 0.30, y: 0.66), to: CGPoint(x: 0.74, y: 0.30),
              scale: (1.12, 0.94), duration: 47, animated: animated)
        layers.append(b)

        return layers
    }

    // MARK: - Slipstream

    private struct Band {
        let cycles: Int, amplitude: CGFloat, thickness: CGFloat, y: CGFloat
        let period: Double, hex: UInt32, alpha: Double, blur: CGFloat
    }

    private static let bands: [Band] = [
        Band(cycles: 1, amplitude: 0.10, thickness: 0.30, y: 0.28, period: 46, hex: 0x3E6E8E, alpha: 0.34, blur: 46),
        Band(cycles: 2, amplitude: 0.06, thickness: 0.16, y: 0.44, period: 33, hex: 0x64A5B4, alpha: 0.24, blur: 34),
        Band(cycles: 1, amplitude: 0.13, thickness: 0.22, y: 0.62, period: 58, hex: 0x2F4E7A, alpha: 0.32, blur: 52),
        Band(cycles: 3, amplitude: 0.04, thickness: 0.09, y: 0.55, period: 25, hex: 0xA8D2D0, alpha: 0.14, blur: 22),
        Band(cycles: 2, amplitude: 0.08, thickness: 0.26, y: 0.80, period: 39, hex: 0x27405F, alpha: 0.40, blur: 44),
    ]

    private static func slipstream(size: CGSize, animated: Bool) -> [CALayer] {
        let w = size.width, h = size.height
        var layers: [CALayer] = [axial([.tg(0x070C15), .tg(0x0D1826), .tg(0x122436)],
                                       frame: CGRect(origin: .zero, size: size))]

        for band in bands {
            let wavelength = w / CGFloat(band.cycles)
            let bandWidth = w * 3
            // Only as tall as the ribbon plus its blur: a full-height layer three screens wide is
            // a lot of empty pixels for the compositor to move every frame.
            let stripHeight = min(h, band.amplitude * h * 2 + band.thickness * h + band.blur * 6)

            let shape = CALayer()
            shape.bounds = CGRect(x: 0, y: 0, width: bandWidth, height: stripHeight)
            shape.contentsGravity = .resize
            shape.contents = softImage(size: CGSize(width: bandWidth, height: stripHeight),
                                       scale: 1.0 / 3.0, blur: band.blur) { ctx in
                ctx.setFillColor(.tg(band.hex, opacity: band.alpha))
                ctx.addPath(wavePath(width: bandWidth, height: stripHeight,
                                     wavelength: wavelength,
                                     amplitude: band.amplitude * h,
                                     thickness: band.thickness * h))
                ctx.fillPath()
            }

            let centreY = band.y * h
            shape.position = CGPoint(x: bandWidth / 2, y: centreY)
            if animated {
                let slide = CABasicAnimation(keyPath: "position.x")
                slide.fromValue = bandWidth / 2
                slide.toValue = bandWidth / 2 - w        // exactly `cycles` wavelengths
                slide.duration = band.period
                slide.repeatCount = .infinity
                slide.timingFunction = CAMediaTimingFunction(name: .linear)
                slide.isRemovedOnCompletion = false
                shape.add(slide, forKey: "flow")
            }
            layers.append(shape)
        }
        return layers
    }

    /// A ribbon whose centre line is a sine wave. Periodic in `wavelength`, so translating by any
    /// whole number of wavelengths is invisible.
    private static func wavePath(width: CGFloat, height: CGFloat,
                                 wavelength: CGFloat, amplitude: CGFloat,
                                 thickness: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let mid = height / 2
        let step: CGFloat = 8
        func y(_ x: CGFloat, _ offset: CGFloat) -> CGFloat {
            mid + sin(x / max(wavelength, 1) * 2 * .pi) * amplitude + offset
        }
        path.move(to: CGPoint(x: 0, y: y(0, -thickness / 2)))
        var x: CGFloat = 0
        while x <= width { path.addLine(to: CGPoint(x: x, y: y(x, -thickness / 2))); x += step }
        x = width
        while x >= 0 { path.addLine(to: CGPoint(x: x, y: y(x, thickness / 2))); x -= step }
        path.closeSubpath()
        return path
    }

    // MARK: - Fireflies

    private static func fireflies(size: CGSize, animated: Bool) -> [CALayer] {
        let w = size.width, h = size.height
        var layers: [CALayer] = [axial([.tg(0x070B0C), .tg(0x0E1616), .tg(0x14201C)],
                                       frame: CGRect(origin: .zero, size: size))]

        let ground = radial(.tg(0x22382F, opacity: 0.62), diameter: max(w, h) * 1.5)
        ground.position = CGPoint(x: w * 0.5, y: h * 0.88)
        layers.append(ground)

        var rng = SeededRandom(seed: 0x7ACE_B00C)
        let palette: [UInt32] = [0xFFE7A6, 0xE6F0AE, 0xFFD59B, 0xC6F0D6]

        for _ in 0..<54 {
            let x = CGFloat.random(in: 0.02...0.98, using: &rng)
            let y = CGFloat.random(in: 0.04...0.96, using: &rng)
            let dx = CGFloat.random(in: -0.14...0.14, using: &rng)
            let dy = CGFloat.random(in: -0.10...0.10, using: &rng)
            let dot = CGFloat.random(in: 2.6...7.5, using: &rng)
            let period = Double.random(in: 18...38, using: &rng)
            let breath = Double.random(in: 4.5...11.0, using: &rng)
            let hex = palette[Int.random(in: 0..<palette.count, using: &rng)]
            let peak = Double.random(in: 0.45...0.95, using: &rng)

            let mote = CALayer()
            mote.frame = CGRect(x: 0, y: 0, width: dot * 10, height: dot * 10)
            mote.compositingFilter = "screenBlendMode"

            let glow = radial(.tg(hex, opacity: 0.38), diameter: dot * 10)
            glow.position = CGPoint(x: dot * 5, y: dot * 5)
            mote.addSublayer(glow)

            let core = CALayer()
            core.bounds = CGRect(x: 0, y: 0, width: dot, height: dot)
            core.position = CGPoint(x: dot * 5, y: dot * 5)
            core.cornerRadius = dot / 2
            core.backgroundColor = .tg(hex, opacity: 0.92)
            mote.addSublayer(core)

            mote.position = CGPoint(x: x * w, y: y * h)
            mote.opacity = animated ? Float(peak) : Float(peak * 0.7)

            if animated {
                let move = CABasicAnimation(keyPath: "position")
                move.fromValue = CGPoint(x: x * w, y: y * h)
                move.toValue = CGPoint(x: (x + dx) * w, y: (y + dy) * h)
                move.duration = period
                move.autoreverses = true
                move.repeatCount = .infinity
                move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                move.timeOffset = Double.random(in: 0...period, using: &rng)
                mote.add(move, forKey: "drift")

                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 0.10
                pulse.toValue = peak
                pulse.duration = breath
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                pulse.timeOffset = Double.random(in: 0...breath, using: &rng)
                mote.add(pulse, forKey: "breath")
            }
            layers.append(mote)
        }
        return layers
    }

    // MARK: - Topography

    private static func topography(size: CGSize, animated: Bool) -> [CALayer] {
        let w = size.width, h = size.height
        var layers: [CALayer] = [axial([.tg(0x0C1016), .tg(0x151A24), .tg(0x1D2432)],
                                       frame: CGRect(origin: .zero, size: size))]

        let lineCount = 26
        let spacing = h / CGFloat(lineCount - 1)
        let states = 4                 // morph targets; the last equals the first so it loops
        let period: Double = 46

        for i in 0..<lineCount {
            let t = CGFloat(i) / CGFloat(lineCount - 1)
            var paths: [CGPath] = (0..<states).map {
                contour(row: t, baseY: CGFloat(i) * spacing, width: w,
                        amplitude: spacing * 1.7, phase: Double($0) / Double(states) * 2 * .pi)
            }
            paths.append(paths[0])

            let line = CAShapeLayer()
            line.frame = CGRect(origin: .zero, size: size)
            line.path = paths[0]
            line.fillColor = nil
            line.lineWidth = 1.1
            line.lineJoin = .round
            line.strokeColor = .tg(0xAEC8EA, opacity: 0.12 + 0.20 * Double(sin(Double(t) * .pi)))

            if animated {
                let morph = CAKeyframeAnimation(keyPath: "path")
                morph.values = paths
                morph.duration = period
                morph.repeatCount = .infinity
                morph.calculationMode = .linear
                morph.timeOffset = Double(i) / Double(lineCount) * period
                line.add(morph, forKey: "survey")
            }
            layers.append(line)
        }

        let vignette = radial(.tg(0x05070B, opacity: 0), diameter: max(w, h) * 1.6)
        vignette.colors = [CGColor.tg(0x05070B, opacity: 0), CGColor.tg(0x05070B, opacity: 0.5)]
        vignette.position = CGPoint(x: w / 2, y: h / 2)
        layers.append(vignette)

        return layers
    }

    private static func contour(row: CGFloat, baseY: CGFloat, width: CGFloat,
                                amplitude: CGFloat, phase: Double) -> CGPath {
        let path = CGMutablePath()
        let step: CGFloat = 9
        let r = Double(row)
        var x: CGFloat = -step
        var first = true
        while x <= width + step {
            let u = Double(x / max(width, 1))
            let e = sin(u * 4.1 + phase + r * 2.7) * 0.55
                  + sin(u * 7.7 - phase * 0.6 + r * 5.1) * 0.28
                  + sin(u * 1.9 + phase * 0.4 - r * 1.3) * 0.40
            let point = CGPoint(x: x, y: baseY + CGFloat(e) * amplitude)
            if first { path.move(to: point); first = false } else { path.addLine(to: point) }
            x += step
        }
        return path
    }

    // MARK: - Aurora

    private struct Curtain {
        let x: CGFloat, width: CGFloat, height: CGFloat
        let tilt: CGFloat, dx: CGFloat, scale: CGFloat, period: Double
        let hex: UInt32, alpha: Double
    }

    private static let curtains: [Curtain] = [
        Curtain(x: 0.24, width: 0.30, height: 0.95, tilt: -9, dx: 0.07, scale: 1.12, period: 41, hex: 0x66E0A8, alpha: 0.26),
        Curtain(x: 0.48, width: 0.24, height: 1.05, tilt: 6, dx: -0.06, scale: 0.90, period: 53, hex: 0x8FD8F0, alpha: 0.20),
        Curtain(x: 0.70, width: 0.34, height: 0.88, tilt: -4, dx: 0.05, scale: 1.16, period: 34, hex: 0xB49BE8, alpha: 0.19),
        Curtain(x: 0.10, width: 0.22, height: 0.75, tilt: 12, dx: -0.04, scale: 1.08, period: 61, hex: 0x7FE6C4, alpha: 0.15),
    ]

    private static func aurora(size: CGSize, animated: Bool) -> [CALayer] {
        let w = size.width, h = size.height
        var layers: [CALayer] = [axial([.tg(0x05070F), .tg(0x0A1120), .tg(0x111C2E)],
                                       frame: CGRect(origin: .zero, size: size))]

        layers.append(starfield(size: size))

        for c in curtains {
            // Padded so the blur has somewhere to fall off instead of clipping at the edge.
            let pad: CGFloat = 220
            let inner = CGSize(width: c.width * w, height: c.height * h)
            let outer = CGSize(width: inner.width + pad * 2, height: inner.height + pad * 2)

            let curtain = CALayer()
            curtain.bounds = CGRect(origin: .zero, size: outer)
            curtain.contentsGravity = .resize
            curtain.compositingFilter = "screenBlendMode"
            curtain.contents = softImage(size: outer, scale: 1.0 / 3.0, blur: 78) { ctx in
                let rect = CGRect(x: pad, y: pad, width: inner.width, height: inner.height)
                guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                colors: [CGColor.tg(c.hex, opacity: c.alpha),
                                                         CGColor.tg(c.hex, opacity: 0)] as CFArray,
                                                locations: [0, 1]) else { return }
                ctx.saveGState()
                ctx.clip(to: rect)
                ctx.drawLinearGradient(gradient,
                                       start: CGPoint(x: rect.midX, y: rect.maxY),
                                       end: CGPoint(x: rect.midX, y: rect.minY),
                                       options: [])
                ctx.restoreGState()
            }
            curtain.position = CGPoint(x: c.x * w, y: h * 0.42)
            curtain.transform = CATransform3DMakeRotation(c.tilt * .pi / 180, 0, 0, 1)

            if animated {
                let slide = CABasicAnimation(keyPath: "position.x")
                slide.fromValue = c.x * w
                slide.toValue = (c.x + c.dx) * w
                slide.duration = c.period
                slide.autoreverses = true
                slide.repeatCount = .infinity
                slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                curtain.add(slide, forKey: "sway")

                // Rotation lives in `transform`, so breathe with a separate scale keypath.
                let breathe = CABasicAnimation(keyPath: "transform.scale.y")
                breathe.fromValue = 1.0
                breathe.toValue = c.scale
                breathe.duration = c.period * 0.8
                breathe.autoreverses = true
                breathe.repeatCount = .infinity
                breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                curtain.add(breathe, forKey: "breathe")
            }
            layers.append(curtain)
        }

        let horizon = CAGradientLayer()
        horizon.frame = CGRect(x: 0, y: h * 0.5, width: w, height: h * 0.5)
        horizon.colors = [CGColor.tg(0x05070F, opacity: 0), CGColor.tg(0x05070F, opacity: 0.75)]
        horizon.startPoint = CGPoint(x: 0.5, y: 0)
        horizon.endPoint = CGPoint(x: 0.5, y: 1)
        layers.append(horizon)

        return layers
    }

    /// 90 static dots drawn once into a single layer's contents — cheaper than 90 layers.
    private static func starfield(size: CGSize) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: size)
        let scale: CGFloat = 2
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return layer }

        var rng = SeededRandom(seed: 0x5EED_5741)
        for _ in 0..<90 {
            let x = CGFloat.random(in: 0...1, using: &rng) * CGFloat(width)
            let y = CGFloat.random(in: 0.3...1, using: &rng) * CGFloat(height)
            let r = CGFloat.random(in: 0.8...1.8, using: &rng) * scale
            let a = CGFloat.random(in: 0.12...0.46, using: &rng)
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: a))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        layer.contents = ctx.makeImage()
        layer.contentsGravity = .resize
        return layer
    }

    // MARK: - Primitives

    private static func axial(_ colors: [CGColor], frame: CGRect) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.frame = frame
        layer.colors = colors
        layer.startPoint = CGPoint(x: 0.5, y: 0)
        layer.endPoint = CGPoint(x: 0.5, y: 1)
        return layer
    }

    private static func radial(_ inner: CGColor, diameter: CGFloat) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.type = .radial
        layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        layer.colors = [inner, inner.copy(alpha: 0) ?? inner]
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 1)
        layer.compositingFilter = "screenBlendMode"
        return layer
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Draws `draw` into an offscreen bitmap at `scale`, blurs it once, and hands back a CGImage
    /// for a layer's `contents`. Baking the blur beats a live `CALayer.filters` blur twice over:
    /// it costs nothing per frame, and it does not depend on `layerUsesCoreImageFilters`.
    private static func softImage(size: CGSize, scale: CGFloat, blur: CGFloat,
                                  draw: (CGContext) -> Void) -> CGImage? {
        let pixelWidth = Int((size.width * scale).rounded())
        let pixelHeight = Int((size.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0,
              let ctx = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        draw(ctx)
        guard let flat = ctx.makeImage() else { return nil }

        let source = CIImage(cgImage: flat)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return flat }
        filter.setValue(source.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(blur * scale, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return flat }
        return ciContext.createCGImage(output.cropped(to: source.extent), from: source.extent)
            ?? flat
    }

    private static func drift(_ layer: CALayer, size: CGSize,
                              from: CGPoint, to: CGPoint,
                              scale: (CGFloat, CGFloat), duration: Double, animated: Bool) {
        let start = CGPoint(x: from.x * size.width, y: from.y * size.height)
        let end = CGPoint(x: to.x * size.width, y: to.y * size.height)
        layer.position = start
        guard animated else { return }

        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = start
        move.toValue = end
        move.duration = duration
        move.autoreverses = true
        move.repeatCount = .infinity
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(move, forKey: "drift")

        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = scale.0
        breathe.toValue = scale.1
        breathe.duration = duration
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(breathe, forKey: "breathe")
    }
}
