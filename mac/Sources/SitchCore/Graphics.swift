import AppKit
import CoreGraphics

// Geometry and drawing helpers shared by the whole pipeline. Document space is pixels with a
// TOP-LEFT origin (y down), exactly like the Windows build; every context the renderer draws
// into is flipped to match, so annotation code ports line for line.

public extension CGPoint {
    static func + (a: CGPoint, v: CGVector) -> CGPoint { CGPoint(x: a.x + v.dx, y: a.y + v.dy) }
    static func - (a: CGPoint, v: CGVector) -> CGPoint { CGPoint(x: a.x - v.dx, y: a.y - v.dy) }
    static func - (a: CGPoint, b: CGPoint) -> CGVector { CGVector(dx: a.x - b.x, dy: a.y - b.y) }
    static func += (a: inout CGPoint, v: CGVector) { a = a + v }
}

public extension CGVector {
    var length: CGFloat { (dx * dx + dy * dy).squareRoot() }
    var lengthSquared: CGFloat { dx * dx + dy * dy }
    static func * (v: CGVector, s: CGFloat) -> CGVector { CGVector(dx: v.dx * s, dy: v.dy * s) }
    static func / (v: CGVector, s: CGFloat) -> CGVector { CGVector(dx: v.dx / s, dy: v.dy / s) }
    static prefix func - (v: CGVector) -> CGVector { CGVector(dx: -v.dx, dy: -v.dy) }
    static func + (a: CGVector, b: CGVector) -> CGVector { CGVector(dx: a.dx + b.dx, dy: a.dy + b.dy) }
    static func dot(_ a: CGVector, _ b: CGVector) -> CGFloat { a.dx * b.dx + a.dy * b.dy }
}

public extension CGRect {
    /// The normalized rect spanning two corners (WPF's `new Rect(a, b)`).
    init(corner a: CGPoint, _ b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    func inflated(by d: CGFloat) -> CGRect { insetBy(dx: -d, dy: -d) }
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

public func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

public func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let ab = b - a
    let len2 = ab.lengthSquared
    if len2 < 1e-6 { return (p - a).length }
    let t = clamp(CGVector.dot(p - a, ab) / len2, 0, 1)
    return (p - (a + ab * t)).length
}

/// An integer pixel rectangle (WPF `Int32Rect`): crops, obscure regions, capture rects.
public struct PixelRect: Codable, Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// 8-bit sRGB color with alpha, parsed from / written as "#RRGGBB" or "#AARRGGBB" (WPF order).
public struct RGBAColor: Equatable, Hashable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8, a: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt32(s, radix: 16) else { return nil }
        if s.count == 6 {
            self.init(UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF))
        } else {
            self.init(UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF), UInt8(v >> 24 & 0xFF))
        }
    }

    public var hex: String {
        a == 255
            ? String(format: "#%02X%02X%02X", r, g, b)
            : String(format: "#%02X%02X%02X%02X", a, r, g, b)
    }

    public func withAlpha(_ alpha: UInt8) -> RGBAColor { RGBAColor(r, g, b, alpha) }

    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    public var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    public static let pink = RGBAColor(0xFF, 0x33, 0x66)
    public static let yellow = RGBAColor(0xFF, 0xD6, 0x0A)
    public static let white = RGBAColor(255, 255, 255)
    public static let black = RGBAColor(0, 0, 0)

    public static func hex(_ s: String) -> RGBAColor { RGBAColor(hex: s) ?? .pink }
}

public enum Draw {
    /// A bitmap context whose user space is document pixels with a top-left origin.
    public static func makeContext(width: Int, height: Int, colorSpace: CGColorSpace? = nil) -> CGContext? {
        guard let ctx = CGContext(
            data: nil, width: max(1, width), height: max(1, height), bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        return ctx
    }

    /// The image's own RGB color space when a bitmap context can use it (keeps Display P3
    /// captures from being squeezed into sRGB); sRGB otherwise.
    public static func colorSpace(for image: CGImage) -> CGColorSpace {
        if let cs = image.colorSpace, cs.model == .rgb, cs.supportsOutput { return cs }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    /// Draws an image upright into a top-left-origin (flipped) context.
    public static func image(_ image: CGImage, in rect: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// Runs AppKit text drawing against a flipped CGContext (AppKit draws into NSGraphicsContext.current).
    public static func withAppKit(_ ctx: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Text layout via AppKit attributed strings: multi-line, font fallback (emoji, CJK) for free.
public enum TextLayout {
    /// "System" is the platform UI font (SF Pro) — the Mac stand-in for Windows' Segoe UI.
    public static let systemFamily = "System"

    public static func font(family: String, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        let base: NSFont
        if family == systemFamily || family.isEmpty {
            base = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        } else {
            let fm = NSFontManager.shared
            base = fm.font(withFamily: family, traits: bold ? .boldFontMask : [], weight: bold ? 9 : 5, size: size)
                ?? NSFont(name: family, size: size)
                ?? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        }
        guard italic else { return base }
        let traits = base.fontDescriptor.symbolicTraits.union(.italic)
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: size) ?? base
    }

    public static func string(_ text: String, font: NSFont, color: RGBAColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color.nsColor])
    }

    private static let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    public static func size(_ s: NSAttributedString) -> CGSize {
        let r = s.boundingRect(with: CGSize(width: 100_000, height: 100_000), options: options)
        return CGSize(width: ceil(r.width), height: ceil(r.height))
    }

    /// Draws with the layout box's top-left at `origin` (context must be top-left origin).
    public static func draw(_ s: NSAttributedString, at origin: CGPoint, in ctx: CGContext) {
        let size = size(s)
        Draw.withAppKit(ctx) {
            s.draw(with: CGRect(origin: origin, size: size), options: options)
        }
    }
}
