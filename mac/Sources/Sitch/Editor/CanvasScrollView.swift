import AppKit

/// Scroll view hosting the canvas: centers the document when it is smaller than the viewport
/// (XAML: HorizontalAlignment/VerticalAlignment=Center) and turns ⌘-scroll / pinch into zoom.
@MainActor
final class CanvasScrollView: NSScrollView {
    var onZoom: ((CGFloat) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        contentView = CenteringClipView()
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = true
        backgroundColor = Theme.canvas
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            onZoom?(event.scrollingDeltaY > 0 ? 1.15 : 1 / 1.15)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        onZoom?(1 + event.magnification)
    }
}

@MainActor
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposed: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposed)
        guard let doc = documentView else { return r }
        if doc.frame.width < r.width { r.origin.x = (doc.frame.width - r.width) / 2 }
        if doc.frame.height < r.height { r.origin.y = (doc.frame.height - r.height) / 2 }
        return r
    }
}

/// Document view of the scroll view: the canvas inset by an 18pt margin with a thin border
/// (XAML: CanvasHost Margin=18, Border #33000000), plus the text-editing overlay.
@MainActor
final class CanvasContainer: NSView {
    static let margin: CGFloat = 18
    let canvas: DocumentCanvas

    init(canvas: DocumentCanvas) {
        self.canvas = canvas
        super.init(frame: .zero)
        addSubview(canvas)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    func layoutCanvas() {
        let size = canvas.contentSize
        let m = Self.margin
        setFrameSize(NSSize(width: ceil(size.width) + m * 2, height: ceil(size.height) + m * 2))
        canvas.frame = NSRect(x: m, y: m, width: size.width, height: size.height)
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        // Margin area: hand ⌘-scroll to the scroll view's zoom handling too.
        enclosingScrollView?.scrollWheel(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0x33 / 255.0).setStroke()
        let path = NSBezierPath(rect: canvas.frame.insetBy(dx: -0.5, dy: -0.5))
        path.lineWidth = 1
        path.stroke()
    }
}

/// Bottom-bar handle that drags the flattened image out as a PNG file (+ PNG data).
@MainActor
final class DragOutButton: NSView, NSDraggingSource {
    /// Produces the temp file to drag; nil aborts.
    var makeFile: (() -> URL?)?
    private let button: ChromeButton

    init() {
        button = ChromeButton(.icon, .glyph(ToolIcons.dragHand), toolTip: "Drag me into any app")
        super.init(frame: .zero)
        addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor), button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor), button.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil // the drag starts here, not in the inner button
    }

    override func mouseDown(with event: NSEvent) {
        guard let url = makeFile?() else { return }
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if let data = try? Data(contentsOf: url) { item.setData(data, forType: .png) }
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        let thumb = NSImage(contentsOf: url) ?? NSImage()
        let maxSide: CGFloat = 96
        let scale = min(1, maxSide / max(1, max(thumb.size.width, thumb.size.height)))
        let size = NSSize(width: thumb.size.width * scale, height: thumb.size.height * scale)
        let p = convert(event.locationInWindow, from: nil)
        dragItem.setDraggingFrame(NSRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height),
                                  contents: thumb)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    nonisolated func draggingSession(_ session: NSDraggingSession,
                                     sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
