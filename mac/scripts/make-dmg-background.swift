// Draws the disk-image window background: a soft panel with Sitch's tapered pink arrow pointing
// from the app icon to the Applications shortcut, plus a one-line instruction. Written at 1x and
// 2x; make-dmg.sh merges them into one HiDPI TIFF. Layout must match make-dmg.sh: 600×400 pt
// window, icons centered at (150, 190) and (450, 190).
// Usage (from mac/): swift scripts/make-dmg-background.swift OUT_DIR
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let size = CGSize(width: 600, height: 400)

func hex(_ s: String, _ alpha: CGFloat = 1) -> CGColor {
    let v = UInt32(s.dropFirst(), radix: 16)!
    return CGColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
}

/// Same silhouette as SitchCore's ArrowAnnotation.taperedPath (single-headed).
func taperedArrow(from a: CGPoint, to b: CGPoint, width w: CGFloat) -> CGPath {
    let len = hypot(b.x - a.x, b.y - a.y)
    let dir = CGVector(dx: (b.x - a.x) / len, dy: (b.y - a.y) / len)
    let perp = CGVector(dx: -dir.dy, dy: dir.dx)
    func p(_ o: CGPoint, _ v: CGVector, _ s: CGFloat) -> CGPoint { CGPoint(x: o.x + v.dx * s, y: o.y + v.dy * s) }
    let headLen = min(max(len * 0.30, max(10, w * 1.1)), w * 3.4)
    let headHalf = headLen * 0.42, tailHalf = w * 0.5, neck = max(1.4, w * 0.17)
    let headBase = p(b, dir, -headLen)
    let barbBack = p(headBase, dir, -headLen * 0.10)
    let ctrlBase = p(a, dir, (len - headLen) * 0.58)
    let ctrlOff = neck + (tailHalf - neck) * 0.22
    let path = CGMutablePath()
    path.move(to: p(a, perp, tailHalf))
    path.addQuadCurve(to: p(headBase, perp, neck), control: p(ctrlBase, perp, ctrlOff))
    path.addLine(to: p(barbBack, perp, headHalf))
    path.addLine(to: b)
    path.addLine(to: p(barbBack, perp, -headHalf))
    path.addLine(to: p(headBase, perp, -neck))
    path.addQuadCurve(to: p(a, perp, -tailHalf), control: p(ctrlBase, perp, -ctrlOff))
    path.closeSubpath()
    return path
}

func render(scale: CGFloat) -> Data {
    let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: -scale) // top-left origin, like Finder's icon positions
    ctx.translateBy(x: 0, y: -size.height)

    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [hex("#FAFAFC"), hex("#ECECF1")] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

    // Slight upward sweep reads as "move this over there", the way a Skitch arrow would be drawn.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -2 * scale), blur: 6 * scale, color: hex("#000000", 0.18))
    ctx.addPath(taperedArrow(from: CGPoint(x: 238, y: 206), to: CGPoint(x: 362, y: 178), width: 22))
    ctx.setFillColor(hex("#FF3366"))
    ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let text = NSAttributedString(string: "Drag Sitch to your Applications folder", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0x6E / 255.0, green: 0x6E / 255.0, blue: 0x78 / 255.0, alpha: 1),
        .paragraphStyle: style,
    ])
    text.draw(in: CGRect(x: 0, y: 318, width: size.width, height: 24))
    NSGraphicsContext.restoreGraphicsState()

    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try render(scale: 1).write(to: outDir.appendingPathComponent("background.png"))
try render(scale: 2).write(to: outDir.appendingPathComponent("background@2x.png"))
print("Wrote \(outDir.path)/background{,@2x}.png")
