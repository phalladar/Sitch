import CoreGraphics

public struct RenderContext {
    public var base: CGImage
    public var baseVersion: Int
    public var forExport: Bool

    public init(base: CGImage, baseVersion: Int, forExport: Bool = false) {
        self.base = base; self.baseVersion = baseVersion; self.forExport = forExport
    }
}

/// One annotation object. The pristine capture is immutable; every mark — including the
/// obscure effects — is an object in the document's ordered list, editable until export.
/// All geometry is in document pixels (top-left origin). Reference semantics on purpose: the
/// canvas tracks the selected object by identity, and undo snapshots `clone()` it.
public class Annotation {
    public var color: RGBAColor = .pink
    public var strokeWidth: CGFloat = 6

    public init() {}

    /// Effects (obscure) render beneath the dim layer and all vector marks.
    public var isEffect: Bool { false }
    public var isSpotlight: Bool { false }

    public var bounds: CGRect { .null }
    public func render(_ ctx: CGContext, _ rc: RenderContext) {}
    public func clone() -> Annotation { fatalError("clone() not implemented for \(type(of: self))") }
    public func move(by d: CGVector) {}

    /// Maps every point through `map` (rotate/flip support).
    public func applyTransform(_ map: (CGPoint) -> CGPoint) {}

    public func hitTest(_ p: CGPoint) -> Bool { bounds.inflated(by: 5).contains(p) }

    public func handles() -> [CGPoint] { [] }
    public func moveHandle(_ index: Int, to p: CGPoint) {}

    /// Copies the shared style onto a fresh clone.
    func copyStyle<T: Annotation>(into target: T) -> T {
        target.color = color
        target.strokeWidth = strokeWidth
        return target
    }
}

/// Annotation defined by two free points (arrow, line).
public class TwoPointAnnotation: Annotation {
    public var a: CGPoint = .zero
    public var b: CGPoint = .zero

    override public var bounds: CGRect { CGRect(corner: a, b).inflated(by: strokeWidth * 1.6 + 4) }

    override public func move(by d: CGVector) { a += d; b += d }
    override public func applyTransform(_ map: (CGPoint) -> CGPoint) { a = map(a); b = map(b) }
    override public func hitTest(_ p: CGPoint) -> Bool { distanceToSegment(p, a, b) <= max(7, strokeWidth * 0.9) }
    override public func handles() -> [CGPoint] { [a, b] }
    override public func moveHandle(_ index: Int, to p: CGPoint) { if index == 0 { a = p } else { b = p } }
}

/// Annotation defined by an axis-aligned rectangle (shapes, obscure, spotlight, image…).
public class RectAnnotation: Annotation {
    public var a: CGPoint = .zero
    public var b: CGPoint = .zero

    public var rect: CGRect { CGRect(corner: a, b) }

    override public var bounds: CGRect { rect.inflated(by: strokeWidth / 2 + 4) }

    override public func move(by d: CGVector) { a += d; b += d }
    override public func applyTransform(_ map: (CGPoint) -> CGPoint) { a = map(a); b = map(b) }
    override public func hitTest(_ p: CGPoint) -> Bool { rect.inflated(by: 5).contains(p) }

    /// 8 handles: 4 corners then 4 edge midpoints (order matters for moveHandle).
    override public func handles() -> [CGPoint] { Self.handles(of: rect) }

    public static func handles(of r: CGRect) -> [CGPoint] {
        [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY),
            CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.midY),
            CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY),
        ]
    }

    override public func moveHandle(_ index: Int, to p: CGPoint) {
        let r = rect
        var left = r.minX, top = r.minY, right = r.maxX, bottom = r.maxY
        switch index {
        case 0: left = p.x; top = p.y
        case 1: right = p.x; top = p.y
        case 2: right = p.x; bottom = p.y
        case 3: left = p.x; bottom = p.y
        case 4: top = p.y
        case 5: right = p.x
        case 6: bottom = p.y
        case 7: left = p.x
        default: break
        }
        a = CGPoint(x: left, y: top)
        b = CGPoint(x: right, y: bottom)
    }

    func copyRect<T: RectAnnotation>(into target: T) -> T {
        target.a = a
        target.b = b
        return copyStyle(into: target)
    }
}
