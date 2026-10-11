import CoreGraphics

/// Composition pipeline (canvas preview and export share it):
/// base → obscure effects → spotlight dim → vector marks.
/// Effects flatten before shapes, so blur never smears an annotation.
public enum Renderer {
    /// Draws the full document in doc-pixel space (caller applies zoom/crop transforms; the
    /// context must have a top-left origin).
    public static func draw(_ ctx: CGContext, _ doc: Document, forExport: Bool,
                            spotlightDim: Double, skip: Annotation? = nil) {
        let rc = RenderContext(base: doc.base, baseVersion: doc.baseVersion, forExport: forExport)
        let full = CGRect(x: 0, y: 0, width: doc.width, height: doc.height)

        Draw.image(doc.base, in: full, ctx)

        for a in doc.annotations where a.isEffect && !a.isSpotlight && a !== skip {
            a.render(ctx, rc)
        }

        let spots = doc.annotations.compactMap { $0 as? SpotlightAnnotation }
            .filter { $0 !== skip && $0.rect.width > 1 && $0.rect.height > 1 }
        if !spots.isEmpty {
            // Dim everything, then clear the UNION of the spotlights (overlaps stay bright —
            // an even-odd fill would re-dim them).
            let opacity = clamp(spotlightDim, 0.2, 0.9)
            ctx.saveGState()
            ctx.beginTransparencyLayer(in: full, auxiliaryInfo: nil)
            ctx.setFillColor(CGColor(gray: 0, alpha: opacity))
            ctx.fill(full)
            ctx.setBlendMode(.clear)
            for s in spots { ctx.fill(s.rect) }
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }

        for a in doc.annotations where !a.isEffect && a !== skip {
            a.render(ctx, rc)
        }
    }

    /// Flattens the document (crop applied) to an image at full document resolution.
    public static func renderToImage(_ doc: Document, spotlightDim: Double) -> CGImage? {
        let view = doc.viewRect
        guard let ctx = Draw.makeContext(width: view.width, height: view.height,
                                         colorSpace: Draw.colorSpace(for: doc.base)) else { return nil }
        ctx.clip(to: CGRect(x: 0, y: 0, width: view.width, height: view.height))
        ctx.translateBy(x: CGFloat(-view.x), y: CGFloat(-view.y))
        draw(ctx, doc, forExport: true, spotlightDim: spotlightDim)
        return ctx.makeImage()
    }

    /// Composites an image onto opaque white (JPEG / PDF have no alpha channel).
    public static func flattenToWhite(_ image: CGImage) -> CGImage {
        if image.alphaInfo == .none || image.alphaInfo == .noneSkipLast || image.alphaInfo == .noneSkipFirst {
            return image
        }
        guard let ctx = Draw.makeContext(width: image.width, height: image.height,
                                         colorSpace: Draw.colorSpace(for: image)) else { return image }
        let r = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(r)
        Draw.image(image, in: r, ctx)
        return ctx.makeImage() ?? image
    }
}
