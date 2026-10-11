import CoreGraphics

public enum ArrowStyle: String, CaseIterable, Sendable { case tapered, filled, open, concave }

/// The iconic Skitch-style arrow. A = tail, B = tip.
public final class ArrowAnnotation: TwoPointAnnotation {
    public var style: ArrowStyle = .tapered
    public var doubleHeaded = false

    override public func render(_ ctx: CGContext, _ rc: RenderContext) {
        let v = b - a
        let len = v.length
        if len < 2 { return }
        let dir = v / len
        let perp = CGVector(dx: -dir.dy, dy: dir.dx)
        let w = max(2, strokeWidth)

        // Head scales with arrow length (a short arrow keeps a proportionate head),
        // bounded by the stroke width so extremes stay sane.
        let headLen = clamp(len * (doubleHeaded ? 0.24 : 0.30), max(10, w * 1.1), w * 3.4)
        let headHalf = headLen * 0.42

        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setFillColor(color.cgColor)
        ctx.setStrokeColor(color.cgColor)

        switch style {
        case .tapered:
            ctx.addPath(Self.taperedPath(a, b, dir, perp, w, headLen, headHalf, doubleHeaded))
            ctx.fillPath()

        case .filled:
            ctx.addPath(blockPath(dir, perp, shaft: w * 0.42, headLen, headHalf, notch: false))
            ctx.fillPath()

        case .open:
            ctx.setLineWidth(max(2, w * 0.45))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokeLineSegments(between: [a, b])
            openHead(ctx, b, dir, perp, headLen, headHalf * 1.2)
            if doubleHeaded { openHead(ctx, a, -dir, perp, headLen, headHalf * 1.2) }

        case .concave:
            // Block arrow whose tail edge is notched inward (⇨ feel).
            ctx.addPath(blockPath(dir, perp, shaft: w * 0.55, headLen, headHalf, notch: true))
            ctx.setLineWidth(max(2, w * 0.28))
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
    }

    private func blockPath(_ dir: CGVector, _ perp: CGVector, shaft: CGFloat,
                           _ headLen: CGFloat, _ headHalf: CGFloat, notch: Bool) -> CGPath {
        let tail = doubleHeaded ? a + dir * headLen : a
        let headBase = b - dir * headLen
        let p = CGMutablePath()
        p.move(to: tail + perp * shaft)
        p.addLine(to: headBase + perp * shaft)
        p.addLine(to: headBase + perp * headHalf)
        p.addLine(to: b)
        p.addLine(to: headBase - perp * headHalf)
        p.addLine(to: headBase - perp * shaft)
        p.addLine(to: tail - perp * shaft)
        if doubleHeaded {
            p.addLine(to: a + dir * headLen - perp * headHalf)
            p.addLine(to: a)
            p.addLine(to: a + dir * headLen + perp * headHalf)
        } else if notch {
            p.addLine(to: a + dir * (shaft * 1.2)) // concave notch
        }
        p.closeSubpath()
        return p
    }

    /// The signature Skitch taper: widest at the tail, concave flanks sweeping to a thin
    /// neck, then a sleek head with slightly swept-back barbs.
    static func taperedPath(_ a: CGPoint, _ b: CGPoint, _ dir: CGVector, _ perp: CGVector,
                            _ w: CGFloat, _ headLen: CGFloat, _ headHalf: CGFloat, _ doubleHeaded: Bool) -> CGPath {
        let tailHalf = w * 0.5
        let neck = max(1.4, w * 0.17)
        let headBase = b - dir * headLen
        let barbBack = headBase - dir * (headLen * 0.10) // barbs sweep a touch behind the base

        let p = CGMutablePath()
        if doubleHeaded {
            // Mirrored heads with a gentle belly between the two necks.
            let tailBase = a + dir * headLen
            let tailBarb = tailBase + dir * (headLen * 0.10)
            let mid = tailBase + (headBase - tailBase) * 0.5
            let belly = max(neck * 1.6, tailHalf * 0.5)

            p.move(to: tailBase + perp * neck)
            p.addQuadCurve(to: headBase + perp * neck, control: mid + perp * belly)
            p.addLine(to: barbBack + perp * headHalf)
            p.addLine(to: b)
            p.addLine(to: barbBack - perp * headHalf)
            p.addLine(to: headBase - perp * neck)
            p.addQuadCurve(to: tailBase - perp * neck, control: mid - perp * belly)
            p.addLine(to: tailBarb - perp * headHalf)
            p.addLine(to: a)
            p.addLine(to: tailBarb + perp * headHalf)
        } else {
            // Concave flanks: the control point sits close to the spine so the
            // silhouette sweeps inward instead of ballooning.
            let ctrlBase = a + (headBase - a) * 0.58
            let ctrlOff = neck + (tailHalf - neck) * 0.22

            p.move(to: a + perp * tailHalf)
            p.addQuadCurve(to: headBase + perp * neck, control: ctrlBase + perp * ctrlOff)
            p.addLine(to: barbBack + perp * headHalf)
            p.addLine(to: b)
            p.addLine(to: barbBack - perp * headHalf)
            p.addLine(to: headBase - perp * neck)
            p.addQuadCurve(to: a - perp * tailHalf, control: ctrlBase - perp * ctrlOff)
        }
        p.closeSubpath()
        return p
    }

    private func openHead(_ ctx: CGContext, _ tip: CGPoint, _ dir: CGVector, _ perp: CGVector,
                          _ headLen: CGFloat, _ headHalf: CGFloat) {
        let back = tip - dir * headLen
        ctx.strokeLineSegments(between: [tip, back + perp * headHalf, tip, back - perp * headHalf])
    }

    override public func clone() -> Annotation {
        let c = ArrowAnnotation()
        c.a = a; c.b = b; c.style = style; c.doubleHeaded = doubleHeaded
        return copyStyle(into: c)
    }
}

public final class LineAnnotation: TwoPointAnnotation {
    override public func render(_ ctx: CGContext, _ rc: RenderContext) {
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(max(1, strokeWidth * 0.45))
        ctx.setLineCap(.round)
        ctx.strokeLineSegments(between: [a, b])
        ctx.restoreGState()
    }

    override public func clone() -> Annotation {
        let c = LineAnnotation()
        c.a = a; c.b = b
        return copyStyle(into: c)
    }
}

public final class BoxAnnotation: RectAnnotation {
    /// true = ellipse, false = rectangle.
    public var isEllipse = false
    public var filled = false

    override public func render(_ ctx: CGContext, _ rc: RenderContext) {
        let r = rect
        if r.width < 1 || r.height < 1 { return }
        let path = isEllipse
            ? CGPath(ellipseIn: r, transform: nil)
            : CGPath(roundedRect: r, cornerWidth: 2, cornerHeight: 2, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        if filled {
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()
        } else {
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(max(1, strokeWidth * 0.45))
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    override public func hitTest(_ p: CGPoint) -> Bool {
        let r = rect
        if filled { return r.inflated(by: 5).contains(p) }
        let pad = max(6, strokeWidth * 0.5)
        let outer = r.inflated(by: pad)
        let inner = r.insetBy(dx: pad, dy: pad)
        if isEllipse {
            // Cheap ellipse ring test via normalized radius.
            if r.width < 2 || r.height < 2 { return outer.contains(p) }
            let nx = (p.x - r.midX) / (r.width / 2)
            let ny = (p.y - r.midY) / (r.height / 2)
            let d = nx * nx + ny * ny
            let tol = max(0.18, strokeWidth / min(r.width, r.height) * 2.4)
            return abs(d.squareRoot() - 1) < tol
        }
        return outer.contains(p) && (inner.isNull || inner.width <= 0 || inner.height <= 0 || !inner.contains(p))
    }

    override public func clone() -> Annotation {
        let c = BoxAnnotation()
        c.isEllipse = isEllipse; c.filled = filled
        return copyRect(into: c)
    }
}
