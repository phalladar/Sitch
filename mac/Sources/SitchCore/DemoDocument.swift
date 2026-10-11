import AppKit
import CoreGraphics

/// The synthetic dashboard behind `--demo` and `--shot-region`: a fake marketing page in the
/// spirit of the classic annotation-app demo shot. Same layout as the Windows DemoMode, so
/// the two builds' README screenshots can be compared side by side.
public enum DemoDocument {
    public static let width = 1500, height = 950

    public static func dashboard() -> CGImage? {
        guard let ctx = Draw.makeContext(width: width, height: height) else { return nil }
        let W = CGFloat(width), H = CGFloat(height)

        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                  colors: [RGBAColor.hex("#F2F3F7").cgColor, RGBAColor.hex("#E8EAF0").cgColor] as CFArray,
                                  locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: H), options: [])

        // Browser chrome
        fill(ctx, CGRect(x: 40, y: 30, width: W - 80, height: H - 70), "#FFFFFF", radius: 10)
        fill(ctx, CGRect(x: 40, y: 30, width: W - 80, height: 46), "#EEEFF3")
        for (x, c) in [(64.0, "#FF5F57"), (86.0, "#FEBC2E"), (108.0, "#28C840")] {
            ctx.setFillColor(RGBAColor.hex(c).cgColor)
            ctx.fillEllipse(in: CGRect(x: x - 7, y: 46, width: 14, height: 14))
        }
        fill(ctx, CGRect(x: 140, y: 40, width: W - 260, height: 26), "#FFFFFF", radius: 13)
        text(ctx, "app.example.com/marketing/q3", 158, 45, 13, "#9A9AA2")

        text(ctx, "Q3 — Marketing Performance Dashboard", 90, 110, 30, "#1D1D28", bold: true)
        text(ctx, "Period: Jul 1 — Sep 30   ·   Updated 2 min ago", 92, 152, 14, "#8A8A94")

        // KPI cards
        let cards: [(String, String, String, String)] = [
            ("Total Revenue", "$284,920", "+12.4%", "#28A745"),
            ("New Customers", "1,847", "+8.1%", "#28A745"),
            ("Conversion Rate", "4.8%", "+0.6%", "#28A745"),
            ("Churn", "2.1%", "−0.3%", "#D9534F"),
        ]
        for (i, card) in cards.enumerated() {
            let x = 90 + CGFloat(i) * 335
            fill(ctx, CGRect(x: x, y: 195, width: 305, height: 130), "#FFFFFF", radius: 10, stroke: "#E3E4EA")
            text(ctx, card.0, x + 22, 215, 13, "#8A8A94")
            text(ctx, card.1, x + 22, 240, 30, "#1D1D28", bold: true)
            text(ctx, card.2, x + 22, 288, 14, card.3, bold: true)
        }

        // Table
        fill(ctx, CGRect(x: 90, y: 370, width: 1320, height: 480), "#FFFFFF", radius: 10, stroke: "#E3E4EA")
        let headers = ["Product", "Region", "Sessions", "Conv. rate", "Revenue"]
        let cols: [CGFloat] = [120, 470, 760, 990, 1220]
        for (i, h) in headers.enumerated() { text(ctx, h, cols[i], 395, 13, "#8A8A94", bold: true) }
        ctx.setStrokeColor(RGBAColor.hex("#E9EAEF").cgColor)
        ctx.setLineWidth(1)
        ctx.strokeLineSegments(between: [CGPoint(x: 105, y: 428), CGPoint(x: 1395, y: 428)])

        let rows: [[String]] = [
            ["Aurora Suite", "Worldwide", "12,840", "5.4%", "$48,210"],
            ["Pencil for Tablet", "EU", "8,221", "4.2%", "$32,180"],
            ["Pixel Garage", "US", "21,003", "3.1%", "$28,940"],
            ["Pencil for Desktop", "EU", "6,540", "3.8%", "$19,260"],
            ["Workshop Pro", "LATAM", "4,109", "2.9%", "$11,840"],
            ["Vivo Hosting", "Spain", "3,820", "2.4%", "$9,420"],
            ["Beacon Analytics", "APAC", "2,977", "2.2%", "$7,730"],
        ]
        for (i, row) in rows.enumerated() {
            let y = 450 + CGFloat(i) * 55
            if i % 2 == 1 { fill(ctx, CGRect(x: 105, y: y - 12, width: 1290, height: 46), "#FAFAFC") }
            text(ctx, row[0], cols[0], y, 15, "#2B2B33")
            text(ctx, row[1], cols[1], y, 15, "#6E6E78")
            text(ctx, row[2], cols[2], y, 15, "#2B2B33")
            text(ctx, row[3], cols[3], y, 15, "#2B2B33")
            text(ctx, row[4], cols[4], y, 15, "#2B2B33", bold: true)
        }
        return ctx.makeImage()
    }

    /// Showcase annotations pre-placed for `--demo` (README screenshots, smoke tests).
    public static func annotations() -> [Annotation] {
        let pink = RGBAColor.pink
        let box = BoxAnnotation()
        box.a = CGPoint(x: 78, y: 182); box.b = CGPoint(x: 410, y: 340); box.color = pink; box.strokeWidth = 9

        let hl = HighlightAnnotation()
        hl.color = .yellow; hl.strokeWidth = 40
        hl.points = [CGPoint(x: 102, y: 528), CGPoint(x: 770, y: 528)]

        let ob = ObscureAnnotation()
        ob.a = CGPoint(x: 1185, y: 500); ob.b = CGPoint(x: 1402, y: 660); ob.style = .pixelate

        let arrow = ArrowAnnotation()
        arrow.a = CGPoint(x: 760, y: 128); arrow.b = CGPoint(x: 430, y: 240); arrow.color = pink; arrow.strokeWidth = 20

        let label = TextAnnotation()
        label.position = CGPoint(x: 778, y: 106); label.text = "Best growth in Q3!"; label.color = pink
        label.fontSize = 40; label.bold = true

        let stamp = StampAnnotation()
        stamp.kind = .check; stamp.center = CGPoint(x: 1330, y: 300); stamp.color = .hex("#34C759"); stamp.size = 52

        return [box, hl, ob, arrow, label, stamp]
    }

    /// A ready-to-edit demo document (annotations placed, not dirty).
    public static func document() -> Document? {
        guard let base = dashboard() else { return nil }
        let doc = Document(base: base)
        doc.annotations = annotations()
        return doc
    }

    /// The region-capture overlay illustration against the dashboard (same dim / marquee /
    /// readout visuals as the live overlay) — a privacy-safe README asset.
    public static func regionShot() -> CGImage? {
        guard let bmp = dashboard(), let ctx = Draw.makeContext(width: width, height: height) else { return nil }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let sel = CGRect(x: 320, y: 170, width: 760, height: 560)
        Draw.image(bmp, in: full, ctx)

        ctx.saveGState()
        ctx.addRect(full)
        ctx.addRect(sel)
        ctx.setFillColor(CGColor(gray: 0, alpha: 0x73 / 255.0))
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
        ctx.setStrokeColor(RGBAColor.pink.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(sel)

        let label = TextLayout.string("\(Int(sel.width)) × \(Int(sel.height))",
                                      font: .systemFont(ofSize: 20, weight: .semibold), color: .white)
        let sz = TextLayout.size(label)
        let bg = CGRect(x: sel.maxX + 12, y: sel.maxY + 12, width: sz.width + 16, height: sz.height + 12)
        ctx.addPath(CGPath(roundedRect: bg, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.setFillColor(RGBAColor(0x1E, 0x1E, 0x20, 0xD9).cgColor)
        ctx.fillPath()
        TextLayout.draw(label, at: CGPoint(x: bg.minX + 8, y: bg.minY + 6), in: ctx)
        return ctx.makeImage()
    }

    private static func fill(_ ctx: CGContext, _ r: CGRect, _ hex: String, radius: CGFloat = 0, stroke: String? = nil) {
        let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(RGBAColor.hex(hex).cgColor)
        ctx.fillPath()
        if let stroke {
            ctx.addPath(path)
            ctx.setStrokeColor(RGBAColor.hex(stroke).cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
        }
    }

    private static func text(_ ctx: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat,
                             _ hex: String, bold: Bool = false) {
        let font = NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        TextLayout.draw(TextLayout.string(s, font: font, color: .hex(hex)), at: CGPoint(x: x, y: y), in: ctx)
    }
}
