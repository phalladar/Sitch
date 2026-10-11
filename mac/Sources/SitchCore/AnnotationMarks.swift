import AppKit
import CoreGraphics

public final class TextAnnotation: Annotation {
    public var position: CGPoint = .zero      // top-left, doc px
    public var text = ""
    public var fontFamily = TextLayout.systemFamily
    public var fontSize: CGFloat = 28
    public var bold = true
    public var italic = false

    public var font: NSFont { TextLayout.font(family: fontFamily, size: fontSize, bold: bold, italic: italic) }

    private func attributed(_ c: RGBAColor) -> NSAttributedString {
        TextLayout.string(text.isEmpty ? " " : text, font: font, color: c)
    }

    override public var bounds: CGRect {
        let size = TextLayout.size(attributed(color))
        return CGRect(origin: position, size: CGSize(width: max(size.width, 8), height: max(size.height, 8)))
    }

    override public func render(_ ctx: CGContext, _ rc: RenderContext) {
        if text.isEmpty { return }
        // Subtle contrast halo so text stays readable on any background (Skitch-style).
        TextLayout.draw(attributed(RGBAColor(0, 0, 0, 0x59)), at: position + CGVector(dx: 1.4, dy: 1.4), in: ctx)
        TextLayout.draw(attributed(color), at: position, in: ctx)
    }

    override public func move(by d: CGVector) { position += d }

    override public func applyTransform(_ map: (CGPoint) -> CGPoint) {
        // Text always renders rightward/downward from position, so map the CENTER and
        // recenter — mapping the top-left directly would shift the label by its own
        // extent under flips/rotations.
        let b = bounds
        let c = map(b.center)
        position = CGPoint(x: c.x - b.width / 2, y: c.y - b.height / 2)
    }

    override public func clone() -> Annotation {
        let c = TextAnnotation()
        c.position = position; c.text = text; c.fontFamily = fontFamily; c.fontSize = fontSize
        c.bold = bold; c.italic = italic
        return copyStyle(into: c)
    }
}

public enum StampKind: String, CaseIterable, Sendable { case check, cross, star, dot, number }

/// Badge stamps: check / cross / star / dot, plus auto-incrementing numbers.
public final class StampAnnotation: Annotation {
    public var kind: StampKind = .check
    public var number = 1
    public var center: CGPoint = .zero
    public var size: CGFloat = 46

    override public var bounds: CGRect { CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size) }

    override public func render(_ ctx: CGContext, _ rc: RenderContext) {
        let r = size / 2, s = size
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: size, height: size))

        let white = CGColor(gray: 1, alpha: 1)
        ctx.setStrokeColor(white)
        ctx.setFillColor(white)
        ctx.setLineWidth(max(2.5, s * 0.09))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: center.x + x, y: center.y + y) }

        switch kind {
        case .check:
            ctx.strokeLineSegments(between: [pt(-s * 0.22, s * 0.02), pt(-s * 0.06, s * 0.18),
                                             pt(-s * 0.06, s * 0.18), pt(s * 0.24, -s * 0.16)])
        case .cross:
            ctx.strokeLineSegments(between: [pt(-s * 0.17, -s * 0.17), pt(s * 0.17, s * 0.17),
                                             pt(s * 0.17, -s * 0.17), pt(-s * 0.17, s * 0.17)])
        case .star:
            let p = CGMutablePath()
            for i in 0..<10 {
                let ang = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let rad = i % 2 == 0 ? s * 0.26 : s * 0.115
                let q = pt(cos(ang) * rad, sin(ang) * rad)
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            p.closeSubpath()
            ctx.addPath(p)
            ctx.fillPath()
        case .dot:
            ctx.fillEllipse(in: CGRect(x: center.x - s * 0.13, y: center.y - s * 0.13, width: s * 0.26, height: s * 0.26))
        case .number:
            let font = NSFont.systemFont(ofSize: s * (number < 10 ? 0.52 : 0.42), weight: .bold)
            let str = TextLayout.string(String(number), font: font, color: .white)
            let sz = TextLayout.size(str)
            TextLayout.draw(str, at: CGPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2), in: ctx)
        }
    }

    override public func move(by d: CGVector) { center += d }
    override public func applyTransform(_ map: (CGPoint) -> CGPoint) { center = map(center) }

    // Handle sits ON the badge circle (distance size/2 from center), so the inverse is dist*2.
    override public func handles() -> [CGPoint] {
        [CGPoint(x: center.x + size / 2 * 0.7071, y: center.y + size / 2 * 0.7071)]
    }

    override public func moveHandle(_ index: Int, to p: CGPoint) { size = clamp((p - center).length * 2, 18, 400) }

    override public func clone() -> Annotation {
        let c = StampAnnotation()
        c.kind = kind; c.number = number; c.center = center; c.size = size
        return copyStyle(into: c)
    }
}

/// Emoji sticker (rendered with Apple Color Emoji).
public final class StickerAnnotation: Annotation {
    public var emoji = "😀"
    public var center: CGPoint = .zero
    public var size: CGFloat = 72

    override public var bounds: CGRect { CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size) }

    override public func render(_ ctx: CGContext, _ rc: RenderContext) {
        let font = NSFont(name: "AppleColorEmoji", size: size * 0.8) ?? .systemFont(ofSize: size * 0.8)
        let str = TextLayout.string(emoji, font: font, color: .black)
        let sz = TextLayout.size(str)
        TextLayout.draw(str, at: CGPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2), in: ctx)
    }

    override public func move(by d: CGVector) { center += d }
    override public func applyTransform(_ map: (CGPoint) -> CGPoint) { center = map(center) }

    override public func handles() -> [CGPoint] {
        [CGPoint(x: center.x + size / 2 * 0.7071, y: center.y + size / 2 * 0.7071)]
    }

    override public func moveHandle(_ index: Int, to p: CGPoint) { size = clamp((p - center).length * 2, 20, 600) }

    override public func clone() -> Annotation {
        let c = StickerAnnotation()
        c.emoji = emoji; c.center = center; c.size = size
        return copyStyle(into: c)
    }
}

/// Image-over-image overlay.
public final class ImageAnnotation: RectAnnotation {
    public var source: CGImage?

    override public func render(_ ctx: CGContext, _ rc: RenderContext) {
        guard let source else { return }
        let r = rect
        if r.width < 1 || r.height < 1 { return }
        Draw.image(source, in: r, ctx)
    }

    override public func clone() -> Annotation {
        let c = ImageAnnotation()
        c.source = source
        return copyRect(into: c)
    }
}

/// Freehand stroke; also the base for the highlighter.
public class PenAnnotation: Annotation {
    public var points: [CGPoint] = []

    var effectiveWidth: CGFloat { max(1.5, strokeWidth * 0.45) }
    var strokeOpacity: CGFloat { 1.0 }

    override public var bounds: CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .inflated(by: effectiveWidth / 2 + 4)
    }

    override public func render(_ ctx: CGContext, _ rc: RenderContext) {
        if points.count < 2 { return }
        ctx.saveGState()
        ctx.setStrokeColor(color.withAlpha(UInt8(255 * strokeOpacity)).cgColor)
        ctx.setLineWidth(effectiveWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        // One path, one stroke: self-overlaps of a translucent highlight don't double up.
        ctx.addLines(between: points)
        ctx.strokePath()
        ctx.restoreGState()
    }

    override public func hitTest(_ p: CGPoint) -> Bool {
        let tol = max(7, effectiveWidth * 0.7)
        for i in points.indices.dropFirst() where distanceToSegment(p, points[i - 1], points[i]) <= tol {
            return true
        }
        return false
    }

    override public func move(by d: CGVector) { points = points.map { $0 + d } }
    override public func applyTransform(_ map: (CGPoint) -> CGPoint) { points = points.map(map) }

    override public func clone() -> Annotation { cloneInto(PenAnnotation()) }

    func cloneInto(_ target: PenAnnotation) -> Annotation {
        target.points = points
        return copyStyle(into: target)
    }
}

/// Translucent marker wash — multiply-blend feel via opacity (default yellow).
public final class HighlightAnnotation: PenAnnotation {
    override var effectiveWidth: CGFloat { max(10, strokeWidth) }
    override var strokeOpacity: CGFloat { 0.42 }

    override public func clone() -> Annotation { cloneInto(HighlightAnnotation()) }
}
