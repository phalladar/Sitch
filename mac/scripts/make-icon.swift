// Draws the Sitch app icon (pink rounded square, white tapered arrow) at every .iconset size and
// packs it with iconutil. A vector redraw of windows/Sitch/Assets/sitch.ico — which tops out at
// 256 px — laid out on Apple's 1024 grid (824-px body, 100-px margin) so it sits right in the Dock.
// Usage (from mac/): swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"

// Arrow outline in the .ico's 256-px design space: tip, barb, notch, tail, tail, notch, barb.
let arrow: [CGPoint] = [(188, 73), (171, 161), (144, 134), (96, 213), (49, 165), (127, 117), (101, 90)]
    .map { CGPoint(x: $0.0, y: $0.1) }

func render(_ px: Int) -> Data {
    let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let k = CGFloat(px) / 1024
    // Shadows are specified in device space, so scale them by hand; CTM flips to the .ico's top-left origin.
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k, color: CGColor(gray: 0, alpha: 0.3))
    ctx.scaleBy(x: k, y: -k)
    ctx.translateBy(x: 0, y: -1024)

    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                       cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0.2, blue: 0.4, alpha: 1)) // #FF3366
    ctx.fillPath()

    let s: CGFloat = 824 / 256
    ctx.addLines(between: arrow.map { CGPoint(x: 100 + $0.x * s, y: 100 + $0.y * s) })
    ctx.closePath()
    ctx.setFillColor(.white)
    ctx.fillPath()
    ctx.endTransparencyLayer() // one shadow for the whole tile, none cast by the arrow onto it

    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", output, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(output)")
