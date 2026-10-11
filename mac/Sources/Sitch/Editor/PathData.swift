import CoreGraphics
import Foundation

/// Minimal SVG / XAML path-data parser (absolute M L H V C Q A Z, implicit command repeats,
/// "F0"/"F1" fill-rule prefix) so the Windows glyph strings are reused verbatim.
enum PathData {
    struct Parsed {
        let path: CGPath
        /// XAML "F0" = even-odd; default (and "F1") = nonzero.
        let evenOdd: Bool
    }

    static func parse(_ data: String) -> Parsed {
        var s = data.trimmingCharacters(in: .whitespaces)
        var evenOdd = true // XAML Geometry.Parse defaults to EvenOdd unless "F1" is given
        if s.hasPrefix("F0") { evenOdd = true; s.removeFirst(2) } else if s.hasPrefix("F1") { evenOdd = false; s.removeFirst(2) }

        let tokens = tokenize(s)
        let p = CGMutablePath()
        var i = 0
        var cmd: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero

        func num() -> CGFloat {
            guard i < tokens.count, case .number(let v) = tokens[i] else { return 0 }
            i += 1
            return v
        }
        func hasNumber() -> Bool {
            if i < tokens.count, case .number = tokens[i] { return true }
            return false
        }
        func point() -> CGPoint { let x = num(); return CGPoint(x: x, y: num()) }

        while i < tokens.count {
            if case .command(let c) = tokens[i] { cmd = c; i += 1 }
            switch cmd {
            case "M":
                current = point(); start = current
                p.move(to: current)
                cmd = "L" // subsequent pairs are implicit line-tos
            case "L":
                current = point(); p.addLine(to: current)
            case "H":
                current = CGPoint(x: num(), y: current.y); p.addLine(to: current)
            case "V":
                current = CGPoint(x: current.x, y: num()); p.addLine(to: current)
            case "C":
                let c1 = point(), c2 = point()
                current = point()
                p.addCurve(to: current, control1: c1, control2: c2)
            case "Q":
                let c1 = point()
                current = point()
                p.addQuadCurve(to: current, control: c1)
            case "A":
                let rx = num(), ry = num(), rot = num(), large = num() != 0, sweep = num() != 0
                let end = point()
                addArc(p, from: current, to: end, rx: rx, ry: ry, rotationDeg: rot, largeArc: large, sweep: sweep)
                current = end
            case "Z", "z":
                p.closeSubpath()
                current = start
                // A Z followed by numbers is malformed; stop rather than loop forever.
                if hasNumber() { i += 1 }
                continue
            default:
                i += 1 // unsupported command: skip a token
            }
        }
        return Parsed(path: p, evenOdd: evenOdd)
    }

    private enum Token { case command(Character), number(CGFloat) }

    private static func tokenize(_ s: String) -> [Token] {
        var out: [Token] = []
        var buf = ""
        func flush() {
            if !buf.isEmpty, let v = Double(buf) { out.append(.number(CGFloat(v))) }
            buf = ""
        }
        for ch in s {
            if ch.isLetter && ch != "e" && ch != "E" {
                flush(); out.append(.command(ch))
            } else if ch == "," || ch == " " || ch == "\n" || ch == "\t" {
                flush()
            } else if ch == "-" && !buf.isEmpty && !buf.hasSuffix("e") && !buf.hasSuffix("E") {
                flush(); buf.append(ch)
            } else if ch == "." && buf.contains(".") && !buf.contains("e") {
                flush(); buf.append(ch)
            } else {
                buf.append(ch)
            }
        }
        flush()
        return out
    }

    /// SVG endpoint arc → center parameterization (SVG spec F.6.5), drawn as a transformed unit arc.
    private static func addArc(_ p: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                               rotationDeg: CGFloat, largeArc: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx < 1e-6 || ry < 1e-6 || p0 == p1 { p.addLine(to: p1); return }
        let phi = rotationDeg * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosP * dx + sinP * dy
        let y1 = -sinP * dx + cosP * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = den == 0 ? 0 : (max(0, num) / den).squareRoot()
        if largeArc == sweep { coef = -coef }
        let cx1 = coef * rx * y1 / ry
        let cy1 = -coef * ry * x1 / rx
        let cx = cosP * cx1 - sinP * cy1 + (p0.x + p1.x) / 2
        let cy = sinP * cx1 + cosP * cy1 + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var dTheta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi } else if sweep && dTheta < 0 { dTheta += 2 * .pi }

        let t = CGAffineTransform(translationX: cx, y: cy).rotated(by: phi).scaledBy(x: rx, y: ry)
        p.addRelativeArc(center: .zero, radius: 1, startAngle: theta1, delta: dTheta, transform: t)
    }
}
