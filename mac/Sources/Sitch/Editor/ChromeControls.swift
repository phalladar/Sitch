import AppKit

/// The editor's custom-drawn buttons, matching windows/Sitch/Themes/Common.xaml:
/// IconButton (flat, hover/pressed wash), SegToggle and RailTool (TileSel background + Accent
/// tint when checked), Primary/Ghost (crop Apply/Cancel). They never take first responder, so
/// clicking one mid text-edit restyles the text instead of ending the edit (XAML Focusable=False).
@MainActor
final class ChromeButton: NSView {
    enum Style { case icon, seg, rail, primary, ghost }

    enum Content {
        case glyph(Glyph)
        case text(String, NSFont)
        case glyphText(Glyph, String, NSFont)
        /// Glyph, label, trailing chevron (save ".png ▾", zoom "100% ▾").
        case menuLabel(Glyph?, String, NSFont)
        /// Free-form drawing in the content rect with the current foreground color.
        case custom(CGSize, (CGRect, NSColor) -> Void)
    }

    let style: Style
    var content: Content { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var isChecked = false { didSet { if isChecked != oldValue { needsDisplay = true } } }
    var isEnabled = true { didSet { if isEnabled != oldValue { needsDisplay = true } } }
    /// Overrides the default glyph color (e.g. the accent-tinted current-tool readout).
    var tint: NSColor? { didSet { needsDisplay = true } }
    var padding: NSEdgeInsets
    var minWidth: CGFloat = 0
    var onClick: (() -> Void)?

    private var hovering = false
    private var pressed = false

    init(_ style: Style, _ content: Content, toolTip: String? = nil, onClick: (() -> Void)? = nil) {
        self.style = style
        self.content = content
        self.onClick = onClick
        switch style {
        case .icon: padding = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        case .seg: padding = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5); minWidth = 30
        case .rail: padding = NSEdgeInsets()
        case .primary, .ghost: padding = NSEdgeInsets(top: 5, left: 14, bottom: 5, right: 14)
        }
        super.init(frame: .zero)
        self.toolTip = toolTip
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var contentSize: CGSize {
        switch content {
        case .glyph(let g): return g.size
        case .text(let s, let f): return textSize(s, f)
        case .glyphText(let g, let s, let f):
            let t = textSize(s, f)
            return CGSize(width: g.size.width + 7 + t.width, height: max(g.size.height, t.height))
        case .menuLabel(let g, let s, let f):
            let t = textSize(s, f)
            let gw = g.map { $0.size.width + 5 } ?? 0
            return CGSize(width: gw + t.width + 5 + 8, height: max(g?.size.height ?? 0, t.height))
        case .custom(let size, _): return size
        }
    }

    private func textSize(_ s: String, _ f: NSFont) -> CGSize {
        let sz = NSAttributedString(string: s, attributes: [.font: f]).size()
        return CGSize(width: ceil(sz.width), height: ceil(sz.height))
    }

    override var intrinsicContentSize: NSSize {
        switch style {
        case .rail: return NSSize(width: 38, height: 34)
        case .seg:
            let c = contentSize
            return NSSize(width: max(minWidth, c.width + padding.left + padding.right), height: 30)
        default:
            let c = contentSize
            return NSSize(width: max(minWidth, c.width + padding.left + padding.right),
                          height: c.height + padding.top + padding.bottom)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        needsDisplay = true
        // Track until mouse-up; fire only if released inside (standard button behavior).
        var inside = true
        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            inside = bounds.contains(convert(e.locationInWindow, from: nil))
            if pressed != inside { pressed = inside; needsDisplay = true }
            if e.type == .leftMouseUp { break }
        }
        pressed = false
        needsDisplay = true
        if inside { onClick?() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    var foreground: NSColor {
        switch style {
        case .primary: return .white
        case .ghost: return Theme.text
        default: return isChecked ? Theme.accent : (tint ?? Theme.glyph)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = style == .rail ? 8 : 6
        let bg: NSColor? = {
            switch style {
            case .primary: return Theme.primary.withAlphaComponent(hovering ? 0.88 : 1)
            case .ghost: return Theme.ghost
            default:
                if pressed { return Theme.pressed }
                if isChecked { return Theme.tileSel }
                if hovering && isEnabled { return Theme.hover }
                return nil
            }
        }()
        if let bg {
            bg.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }

        var fg = foreground
        if !isEnabled { fg = fg.withAlphaComponent(fg.alphaComponent * 0.4) }
        let c = contentSize
        let origin = CGPoint(x: ((bounds.width - c.width) / 2).rounded(), y: ((bounds.height - c.height) / 2).rounded())

        switch content {
        case .glyph(let g):
            g.draw(at: origin, color: fg)
        case .text(let s, let f):
            draw(s, f, fg, at: origin)
        case .glyphText(let g, let s, let f):
            g.draw(at: CGPoint(x: origin.x, y: origin.y + (c.height - g.size.height) / 2), color: fg)
            let t = textSize(s, f)
            draw(s, f, Theme.text, at: CGPoint(x: origin.x + g.size.width + 7, y: origin.y + (c.height - t.height) / 2))
        case .menuLabel(let g, let s, let f):
            var x = origin.x
            if let g {
                g.draw(at: CGPoint(x: x, y: origin.y + (c.height - g.size.height) / 2), color: fg)
                x += g.size.width + 5
            }
            let t = textSize(s, f)
            draw(s, f, Theme.text, at: CGPoint(x: x, y: origin.y + (c.height - t.height) / 2))
            ToolIcons.chevron.draw(at: CGPoint(x: x + t.width + 5, y: origin.y + c.height / 2 - 1.5), color: Theme.textDim)
        case .custom(_, let draw):
            draw(CGRect(origin: origin, size: c), fg)
        }
    }

    private func draw(_ s: String, _ f: NSFont, _ color: NSColor, at p: CGPoint) {
        NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color]).draw(at: p)
    }
}

/// A bar background with a 1pt divider on one edge (top bar, bottom bar, tool rail).
@MainActor
final class BarView: NSView {
    enum Edge { case top, bottom, right }
    private let edge: Edge

    init(divider edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.bar.setFill()
        bounds.fill()
        Theme.divider.setFill()
        switch edge {
        case .top: NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        case .bottom: NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        case .right: NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
        }
    }
}

/// The 1×22 vertical rule between option groups (XAML "Divider" style: 8pt side margins).
@MainActor
final class DividerView: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 17, height: 22) }
    override func draw(_ dirtyRect: NSRect) {
        Theme.divider.setFill()
        NSRect(x: 8, y: (bounds.height - 22) / 2, width: 1, height: 22).fill()
    }
}

@MainActor
func makeLabel(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
               color: NSColor = Theme.text) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.lineBreakMode = .byClipping
    l.setContentHuggingPriority(.required, for: .horizontal)
    return l
}

/// Horizontal stack used for each contextual option group.
@MainActor
func hStack(_ views: [NSView], spacing: CGFloat = 0) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = .horizontal
    s.alignment = .centerY
    s.spacing = spacing
    s.setHuggingPriority(.required, for: .horizontal)
    return s
}
