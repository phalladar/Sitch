import AppKit

enum ToolKind: String, CaseIterable {
    case select, arrow, text, rectangle, ellipse, line, highlight
    case obscure, stamp, pen, spotlight, sticker, image, crop

    var displayName: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .text: "Text"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .highlight: "Highlight"
        case .obscure: "Obscure"
        case .stamp: "Stamp"
        case .pen: "Pen"
        case .spotlight: "Spotlight"
        case .sticker: "Sticker"
        case .image: "Image"
        case .crop: "Crop"
        }
    }
}

/// A vector icon drawn in its own 20-unit design box (the XAML Path boxes, Stretch=None):
/// layers are filled or stroked with the host control's foreground color.
struct Glyph {
    enum Paint { case fill, stroke(CGFloat) }

    struct Layer {
        let path: CGPath
        let evenOdd: Bool
        let paint: Paint
    }

    var layers: [Layer]
    var size: CGSize
    /// Text glyph ("Aa") instead of paths.
    var text: (String, NSFont)?

    init(_ layers: [Layer], size: CGSize = CGSize(width: 20, height: 20)) {
        self.layers = layers
        self.size = size
    }

    static func fill(_ d: String, size: CGSize = CGSize(width: 20, height: 20)) -> Glyph {
        let p = PathData.parse(d)
        return Glyph([Layer(path: p.path, evenOdd: p.evenOdd, paint: .fill)], size: size)
    }

    static func stroke(_ d: String, _ width: CGFloat = 1.7, size: CGSize = CGSize(width: 20, height: 20)) -> Glyph {
        let p = PathData.parse(d)
        return Glyph([Layer(path: p.path, evenOdd: p.evenOdd, paint: .stroke(width))], size: size)
    }

    static func text(_ s: String, _ font: NSFont) -> Glyph {
        var g = Glyph([], size: CGSize(width: 20, height: 20))
        g.text = (s, font)
        return g
    }

    func adding(_ other: Glyph) -> Glyph {
        var g = self
        g.layers += other.layers
        return g
    }

    /// Draws with the box's top-left at `origin` in a flipped view.
    func draw(at origin: CGPoint, color: NSColor) {
        if let (s, font) = text {
            let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
            let sz = str.size()
            str.draw(at: CGPoint(x: origin.x + (size.width - sz.width) / 2, y: origin.y + (size.height - sz.height) / 2))
            return
        }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        let cg = color.cgColor
        for layer in layers {
            ctx.addPath(layer.path)
            switch layer.paint {
            case .fill:
                ctx.setFillColor(cg)
                ctx.fillPath(using: layer.evenOdd ? .evenOdd : .winding)
            case .stroke(let w):
                ctx.setStrokeColor(cg)
                ctx.setLineWidth(w)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }
}

/// Vector glyphs for the tool rail, option groups and bars — path data verbatim from
/// windows/Sitch/Editor/ToolIcons.cs and EditorWindow.xaml.
@MainActor
enum ToolIcons {
    static let railOrder: [ToolKind] = [
        .select, .arrow, .text, .rectangle, .ellipse, .line, .highlight,
        .obscure, .stamp, .pen, .spotlight, .sticker, .image, .crop,
    ]

    static func glyph(_ kind: ToolKind) -> Glyph {
        switch kind {
        case .select: .fill("M5,2 L16,10.2 L10.6,11.3 L13.4,17.2 L11.1,18.3 L8.4,12.4 L5,15.6 Z")
        case .arrow: .fill("M3.6,14.6 L11.2,7 L9.6,5.3 L16,4 L14.7,10.4 L13,8.8 L5.4,16.4 Z")
        case .text: .text("Aa", .systemFont(ofSize: 13, weight: .semibold))
        case .rectangle: .stroke("M4.5,5.5 H15.5 V14.5 H4.5 Z")
        case .ellipse: .stroke("M10,4.5 A5.5,5 0 1 1 9.99,4.5 Z")
        case .line: .stroke("M4.5,15.5 L15.5,4.5")
        case .highlight: .fill("M6,11.5 L11.5,4.5 L15.5,7.5 L10.5,14 L6.8,14 Z M4,16.5 H16 V18 H4 Z")
        case .obscure: .fill("M4,4 H8 V8 H4 Z M12,4 H16 V8 H12 Z M8,8 H12 V12 H8 Z M4,12 H8 V16 H4 Z M12,12 H16 V16 H12 Z")
        case .stamp: Glyph.stroke("M10,3.5 A6.5,6.5 0 1 1 9.99,3.5 Z").adding(.stroke("M7,10.2 L9.2,12.4 L13.4,7.8"))
        case .pen: .stroke("M3.5,15 C5.5,7 8,16.5 10.5,9 C12,5 14.5,7 16.5,5")
        case .spotlight: .stroke("M4,8 V4 H8 M12,4 H16 V8 M16,12 V16 H12 M8,16 H4 V12")
        case .sticker:
            Glyph.stroke("M10,3.5 A6.5,6.5 0 1 1 9.99,3.5 Z M7.2,8.4 A0.4,0.4 0 1 1 7.19,8.4 M12.8,8.4 A0.4,0.4 0 1 1 12.79,8.4")
                .adding(.stroke("M6.8,11.5 Q10,14.5 13.2,11.5"))
        case .image: .stroke("M3.5,4.5 H16.5 V15.5 H3.5 Z M3.5,13 L8,9 L11.5,12 L13.5,10 L16.5,13 M12.8,7.2 A0.9,0.9 0 1 1 12.79,7.2")
        case .crop: .stroke("M6.5,2.5 V13.5 H17.5 M2.5,6.5 H13.5 V17.5")
        }
    }

    // Arrow style option glyphs.
    static let arrowTapered = Glyph.fill("M3,17 L11,8.4 L9.6,7 L16,4 L13,10.4 L11.6,9 L3.8,17.6 Z")
    static let arrowFilled = Glyph.fill("M3,11.5 L10,11.5 L10,14.5 L17,10 L10,5.5 L10,8.5 L3,8.5 Z")
    static let arrowOpen = Glyph.stroke("M3,16 L16,4 M16,4 V10 M16,4 H10")
    static let arrowConcave = Glyph.stroke("M4,11.5 L10,11.5 L10,14.5 L16.5,10 L10,5.5 L10,8.5 L4,8.5 Z")
    static let arrowDouble = Glyph.stroke("M3,10 H17 M6.5,6 L3,10 L6.5,14 M13.5,6 L17,10 L13.5,14")

    // Chrome glyphs (EditorWindow.xaml).
    static let camera = Glyph.stroke(
        "M7,4 L8.5,2 H11.5 L13,4 H16 A1.5,1.5 0 0 1 17.5,5.5 V14.5 A1.5,1.5 0 0 1 16,16 H4 A1.5,1.5 0 0 1 2.5,14.5 V5.5 A1.5,1.5 0 0 1 4,4 Z M10,6.8 A3.4,3.4 0 1 1 9.99,6.8",
        1.6, size: CGSize(width: 20, height: 18))
    static let gear = Glyph.fill(
        "F0 M18.25,7.94 L18.25,12.06 L15.54,12.3 L17.29,14.38 L14.38,17.29 L12.3,15.54 L12.06,18.25 L7.94,18.25 L7.7,15.54 L5.62,17.29 L2.71,14.38 L4.46,12.3 L1.75,12.06 L1.75,7.94 L4.46,7.7 L2.71,5.62 L5.62,2.71 L7.7,4.46 L7.94,1.75 L12.06,1.75 L12.3,4.46 L14.38,2.71 L17.29,5.62 L15.54,7.7 Z M10,7.4 A2.6,2.6 0 1 1 9.99,7.4 Z")
    static let lock = Glyph.stroke("M6,9 V6.5 A4,4 0 0 1 14,6.5 M5,9 H15 V16 H5 Z", 1.6, size: CGSize(width: 20, height: 18))
    static let undo = Glyph.stroke("M8,4 L4,8 L8,12 M4,8 H12 A4,4 0 0 1 16,12 V13", 1.7, size: CGSize(width: 20, height: 17))
    static let redo = Glyph.stroke("M12,4 L16,8 L12,12 M16,8 H8 A4,4 0 0 0 4,12 V13", 1.7, size: CGSize(width: 20, height: 17))
    static let trash = Glyph.stroke("M5,6 H15 M8,6 V4.5 H12 V6 M6,6 L6.8,16 H13.2 L14,6 M8.6,8.5 V13.5 M11.4,8.5 V13.5",
                                    1.6, size: CGSize(width: 20, height: 17))
    static let chevron = Glyph.stroke("M0,0 L4,4 8,0", 1.5, size: CGSize(width: 8, height: 5))
    static let dragHand = Glyph.stroke(
        "M8,11 V4.8 A1.2,1.2 0 0 1 10.4,4.8 V9.5 M10.4,9 A1.2,1.2 0 0 1 12.8,9 V10 M12.8,10 A1.2,1.2 0 0 1 15.2,10.4 V13 A4.5,4.5 0 0 1 10.7,17.5 H10 A4.6,4.6 0 0 1 6.2,15.4 L4.2,12.4 A1.3,1.3 0 0 1 6.2,10.9 L8,12.6 M2.5,6.5 H5.5 M3.4,3.4 L5.6,5.6",
        1.5)
    static let copy = Glyph.stroke("M7,7 H16 V17 H7 Z M7,10 H4 V3 H13 V7", 1.6, size: CGSize(width: 20, height: 19))
    static let save = Glyph.stroke("M10,3 V12 M6.5,8.5 L10,12 L13.5,8.5 M4,14.5 V16 H16 V14.5", 1.6, size: CGSize(width: 20, height: 18))
    static let share = Glyph.stroke("M10,12 V3 M6.8,5.8 L10,2.6 L13.2,5.8 M5,9 H4 V17 H16 V9 H15", 1.6, size: CGSize(width: 20, height: 19))
}
