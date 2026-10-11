import CoreGraphics
import Foundation

public enum ObscureStyle: String, CaseIterable, Sendable { case pixelate, blur, block, stripes }

/// Redaction effect object. Non-destructive: samples the pristine base image each time the
/// covered region changes and is only baked into pixels at export. Pixelate/blur always
/// compute from the full-resolution source; block/stripes are opaque ink — the safe choice
/// for real secrets.
public final class ObscureAnnotation: RectAnnotation {
    public var style: ObscureStyle = .pixelate

    private var cache: CGImage?
    private var cacheKey: (rect: PixelRect, style: ObscureStyle, baseVersion: Int)?

    override public var isEffect: Bool { true }

    override public func render(_ ctx: CGContext, _ rc: RenderContext) {
        let r = rect
        if r.width < 2 || r.height < 2 { return }

        let clipped = r.intersection(CGRect(x: 0, y: 0, width: rc.base.width, height: rc.base.height))
        if clipped.isNull || clipped.width < 2 || clipped.height < 2 { return }
        var ir = PixelRect(x: Int(clipped.minX), y: Int(clipped.minY),
                           width: max(1, Int(clipped.width.rounded())), height: max(1, Int(clipped.height.rounded())))
        ir.width = min(ir.width, rc.base.width - ir.x)
        ir.height = min(ir.height, rc.base.height - ir.y)
        if ir.width < 2 || ir.height < 2 { return }
        let drawRect = ir.cgRect

        switch style {
        case .block:
            ctx.setFillColor(RGBAColor(0x1D, 0x1D, 0x1F).cgColor)
            ctx.fill(drawRect)
            return

        case .stripes:
            ctx.saveGState()
            ctx.setFillColor(RGBAColor(0x1D, 0x1D, 0x1F).cgColor)
            ctx.fill(drawRect)
            ctx.clip(to: drawRect)
            ctx.setStrokeColor(RGBAColor(0x3C, 0x3C, 0x40).cgColor)
            ctx.setLineWidth(7)
            let x = CGFloat(ir.x), y = CGFloat(ir.y), w = CGFloat(ir.width), h = CGFloat(ir.height)
            var o: CGFloat = 0
            while o < w + h {
                ctx.strokeLineSegments(between: [CGPoint(x: x + o, y: y - 4), CGPoint(x: x + o - h - 8, y: y + h + 4)])
                o += 18
            }
            ctx.restoreGState()
            return

        case .pixelate, .blur:
            // Cached full-res sample of the pristine base.
            if cache == nil || cacheKey?.rect != ir || cacheKey?.style != style || cacheKey?.baseVersion != rc.baseVersion {
                cache = style == .pixelate
                    ? EffectRenderer.pixelate(rc.base, ir)
                    : EffectRenderer.boxBlur(rc.base, ir, radius: 12)
                cacheKey = (ir, style, rc.baseVersion)
            }
            if let cache { Draw.image(cache, in: drawRect, ctx) }
        }
    }

    override public func clone() -> Annotation {
        let c = ObscureAnnotation()
        c.style = style
        return copyRect(into: c)
    }
}

/// Spotlight region: the renderer dims everything except the union of all spotlight rects.
/// Multiple spotlights are supported; the object itself draws nothing.
public final class SpotlightAnnotation: RectAnnotation {
    override public var isEffect: Bool { true }
    override public var isSpotlight: Bool { true }

    override public func clone() -> Annotation { copyRect(into: SpotlightAnnotation()) }
}

/// Pixel operations for the obscure effects. Always fed by the full-res pristine base.
public enum EffectRenderer {
    public static func pixelate(_ source: CGImage, _ region: PixelRect) -> CGImage? {
        guard var buf = PixelBuffer(source, region) else { return nil }
        let w = buf.width, h = buf.height, stride = buf.stride
        // Mosaic strength scales with region size; floor keeps small regions genuinely unreadable.
        let block = clamp(min(w, h) / 12, 10, 56)

        buf.pixels.withUnsafeMutableBufferPointer { px in
            var by = 0
            while by < h {
                var bx = 0
                while bx < w {
                    let bw = min(block, w - bx), bh = min(block, h - by)
                    var c0 = 0, c1 = 0, c2 = 0
                    for y in by..<(by + bh) {
                        var row = y * stride + bx * 4
                        for _ in 0..<bw {
                            c0 += Int(px[row]); c1 += Int(px[row + 1]); c2 += Int(px[row + 2])
                            row += 4
                        }
                    }
                    let n = bw * bh
                    let a0 = UInt8(c0 / n), a1 = UInt8(c1 / n), a2 = UInt8(c2 / n)
                    for y in by..<(by + bh) {
                        var row = y * stride + bx * 4
                        for _ in 0..<bw {
                            px[row] = a0; px[row + 1] = a1; px[row + 2] = a2; px[row + 3] = 255
                            row += 4
                        }
                    }
                    bx += block
                }
                by += block
            }
        }
        return buf.makeImage()
    }

    public static func boxBlur(_ source: CGImage, _ region: PixelRect, radius: Int) -> CGImage? {
        guard var buf = PixelBuffer(source, region) else { return nil }
        var tmp = [UInt8](repeating: 0, count: buf.pixels.count)
        let w = buf.width, h = buf.height, s = buf.stride
        // Two box passes ≈ triangular kernel; enough smoothing for redaction preview.
        blurPass(buf.pixels, &tmp, w, h, s, radius, horizontal: true)
        blurPass(tmp, &buf.pixels, w, h, s, radius, horizontal: false)
        blurPass(buf.pixels, &tmp, w, h, s, radius, horizontal: true)
        blurPass(tmp, &buf.pixels, w, h, s, radius, horizontal: false)
        return buf.makeImage()
    }

    private static func blurPass(_ src: [UInt8], _ dst: inout [UInt8], _ w: Int, _ h: Int, _ stride: Int,
                                 _ radius: Int, horizontal: Bool) {
        let outer = horizontal ? h : w
        let inner = horizontal ? w : h
        src.withUnsafeBufferPointer { src in
            dst.withUnsafeMutableBufferPointer { dst in
                for o in 0..<outer {
                    var s0 = 0, s1 = 0, s2 = 0, count = 0
                    func idx(_ i: Int) -> Int { horizontal ? o * stride + i * 4 : i * stride + o * 4 }

                    let rEnd = min(radius, inner - 1)
                    for i in 0...rEnd {
                        let k = idx(i)
                        s0 += Int(src[k]); s1 += Int(src[k + 1]); s2 += Int(src[k + 2])
                        count += 1
                    }
                    for i in 0..<inner {
                        let add = i + radius + 1, remove = i - radius
                        if add < inner {
                            let k = idx(add)
                            s0 += Int(src[k]); s1 += Int(src[k + 1]); s2 += Int(src[k + 2])
                            count += 1
                        }
                        if remove >= 0 {
                            let k = idx(remove)
                            s0 -= Int(src[k]); s1 -= Int(src[k + 1]); s2 -= Int(src[k + 2])
                            count -= 1
                        }
                        let d = idx(i)
                        dst[d] = UInt8(s0 / count)
                        dst[d + 1] = UInt8(s1 / count)
                        dst[d + 2] = UInt8(s2 / count)
                        dst[d + 3] = 255
                    }
                }
            }
        }
    }
}

/// A region of an image as 8-bit RGBA rows (row 0 = top), in the source's color space.
struct PixelBuffer {
    var pixels: [UInt8]
    let width: Int, height: Int, stride: Int
    let colorSpace: CGColorSpace

    init?(_ source: CGImage, _ region: PixelRect) {
        guard let cropped = source.cropping(to: region.cgRect) else { return nil }
        let w = cropped.width, h = cropped.height, s = w * 4
        let cs = Draw.colorSpace(for: source)
        width = w; height = h; stride = s; colorSpace = cs
        var px = [UInt8](repeating: 0, count: s * h)
        let ok = px.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: s, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        pixels = px
    }

    func makeImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
                       space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
