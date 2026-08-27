// TGMenuBar — a minimal SVG `d` attribute parser.
import CoreGraphics
import Foundation

/// Turns an SVG path's `d` attribute into a `CGPath`, in the SVG's own coordinate space
/// (y down, origin top-left). Mapping into a destination rect is `LogoMarkGeometry`'s job.
///
/// Covers everything the designer's export uses and a little more: `M m L l H h V v C c
/// S s Q q T t Z z`, repeated implicit commands, and the shorthand number soup real
/// exporters emit (`.5.5` is two numbers, `1-2` is two numbers, exponents are numbers).
/// Elliptical arcs (`A a`) are *not* supported — `parse` returns nil rather than quietly
/// dropping them, so a future SVG that uses them fails loudly at generation time.
///
/// A verbatim copy lives in `TGOverlay` (the two modules must not depend on each other) and
/// the same routine is inlined in `Support/icon/generate.swift`. If one changes, change all.
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
