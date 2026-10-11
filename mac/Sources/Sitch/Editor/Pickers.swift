import AppKit
import SitchCore

/// Color and emoji pickers shown as popovers (Windows: Popup + UniformGrid, 8 columns).
@MainActor
enum Pickers {
    static let extraColors = [
        "#FF3366", "#FF2D55", "#FF6482", "#FF9500", "#FFB340", "#FFD60A", "#FFE566", "#FFFFFF",
        "#34C759", "#63D97F", "#0A8F3C", "#2E7DF6", "#66A3F8", "#0A4FB5", "#5E5CE6", "#8482EC",
        "#AF52DE", "#C47FE8", "#7A1FA6", "#FF3B30", "#B22219", "#8E8E93", "#48484C", "#1D1D1F",
    ]

    static let emoji = [
        "😀", "😅", "😂", "😊", "😍", "🤔", "😎", "😮",
        "😢", "😡", "🙃", "🤯", "👍", "👎", "👏", "🙏",
        "💪", "👀", "🔥", "⭐", "✨", "🎉", "❤️", "💡",
        "⚠️", "❌", "✅", "❓", "❗", "🚀", "🐛", "🔒",
    ]

    static func showColorPicker(from anchor: NSView, current: RGBAColor, edge: NSRectEdge = .maxY,
                                onPick: @escaping (RGBAColor) -> Void) {
        let popover = NSPopover()
        popover.behavior = .transient
        let grid = gridView(columns: 8, items: extraColors.map { hex in
            let c = RGBAColor.hex(hex)
            let b = ChromeButton(.icon, .custom(CGSize(width: 18, height: 18)) { r, _ in
                swatch(r, c)
            }, toolTip: hex) { [weak popover] in
                onPick(c)
                popover?.close()
            }
            b.padding = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
            return b
        }, cell: 26)

        let field = HexField(string: current.hex)
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.onCommit = { [weak popover] text in
            guard let c = RGBAColor(hex: text) else { return } // invalid hex — leave open
            onPick(c)
            popover?.close()
        }

        let stack = NSStackView(views: [grid, field])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        field.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true

        popover.contentViewController = hosting(stack)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: edge)
    }

    static func showEmojiPicker(from anchor: NSView, onPick: @escaping (String) -> Void) {
        let popover = NSPopover()
        popover.behavior = .transient
        let grid = gridView(columns: 8, items: emoji.map { e in
            ChromeButton(.icon, .text(e, .systemFont(ofSize: 17))) { [weak popover] in
                onPick(e)
                popover?.close()
            }
        }, cell: 32)
        let wrap = NSStackView(views: [grid])
        wrap.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        popover.contentViewController = hosting(wrap)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    /// A filled circle with the faint outline used by every swatch.
    static func swatch(_ r: CGRect, _ c: RGBAColor) {
        let path = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
        c.nsColor.setFill()
        path.fill()
        NSColor(srgbRed: 0x80 / 255, green: 0x80 / 255, blue: 0x88 / 255, alpha: 0x50 / 255).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private static func gridView(columns: Int, items: [NSView], cell: CGFloat) -> NSGridView {
        var rows: [[NSView]] = []
        for start in stride(from: 0, to: items.count, by: columns) {
            rows.append(Array(items[start..<min(start + columns, items.count)]))
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 2
        grid.columnSpacing = 2
        for v in items {
            v.widthAnchor.constraint(equalToConstant: cell).isActive = true
            v.heightAnchor.constraint(equalToConstant: cell).isActive = true
        }
        return grid
    }

    private static func hosting(_ view: NSView) -> NSViewController {
        let vc = NSViewController()
        vc.view = view
        return vc
    }
}

/// Text field that reports Return.
@MainActor
final class HexField: NSTextField, NSTextFieldDelegate {
    var onCommit: ((String) -> Void)?

    convenience init(string: String) {
        self.init(frame: .zero)
        stringValue = string
        delegate = self
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            onCommit?(stringValue.trimmingCharacters(in: .whitespaces))
            return true
        }
        return false
    }
}
