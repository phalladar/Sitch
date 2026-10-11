import AppKit
import SitchCore

/// The annotation canvas. Renders the document at the current zoom, owns hit-testing,
/// selection handles, draft creation and crop-mode chrome. Zoom is "device pixels per
/// document pixel", so 100% is always pixel-perfect regardless of the display's scale
/// (port of windows/Sitch/Editor/DocumentCanvas.cs).
@MainActor
final class DocumentCanvas: NSView {
    var doc: Document? { didSet { needsDisplay = true } }
    weak var owner: EditorWindowController?

    private(set) var zoom: CGFloat = 1
    /// Backing scale of the window's display (Windows: DPI scale).
    private(set) var backingScale: CGFloat = 1

    private(set) var tool: ToolKind = .arrow
    private(set) var selected: Annotation?
    private(set) var draft: Annotation?
    /// Annotation hidden from rendering while its text editor overlay is active.
    var editingText: Annotation? { didSet { needsDisplay = true } }

    private(set) var cropMode = false
    var cropDraft: CGRect = .zero   // doc px

    var onSelectionChanged: (() -> Void)?
    var onCropDraftChanged: (() -> Void)?

    private enum DragKind { case none, create, move, handle, cropHandle, cropMove }
    private var drag: DragKind = .none
    private var handleIndex = -1
    private var dragStartDoc: CGPoint = .zero
    private var cropStart: CGRect = .zero
    private var undoPushed = false

    private static let handleHit: CGFloat = 7

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Geometry

    private var view: PixelRect {
        guard let doc else { return PixelRect(x: 0, y: 0, width: 1, height: 1) }
        return cropMode ? PixelRect(x: 0, y: 0, width: doc.width, height: doc.height) : doc.viewRect
    }

    /// Points per document pixel.
    var pointsPerDoc: CGFloat { zoom / backingScale }

    func toDoc(_ p: CGPoint) -> CGPoint {
        CGPoint(x: CGFloat(view.x) + p.x / pointsPerDoc, y: CGFloat(view.y) + p.y / pointsPerDoc)
    }

    func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - CGFloat(view.x)) * pointsPerDoc, y: (p.y - CGFloat(view.y)) * pointsPerDoc)
    }

    func toView(_ r: CGRect) -> CGRect {
        CGRect(corner: toView(CGPoint(x: r.minX, y: r.minY)), toView(CGPoint(x: r.maxX, y: r.maxY)))
    }

    /// The canvas size in points at the current zoom.
    var contentSize: CGSize {
        CGSize(width: CGFloat(view.width) * pointsPerDoc, height: CGFloat(view.height) * pointsPerDoc)
    }

    func setBackingScale(_ scale: CGFloat) {
        backingScale = max(1, scale)
        owner?.canvasSizeChanged()
        needsDisplay = true
    }

    func setZoom(_ z: CGFloat) {
        zoom = clamp(z, 0.05, 8)
        owner?.canvasSizeChanged()
        needsDisplay = true
        owner?.zoomChanged()
    }

    func setTool(_ t: ToolKind) {
        tool = t
        if t != .select { select(nil) }
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    func select(_ a: Annotation?) {
        if selected === a { return }
        selected = a
        onSelectionChanged?()
        needsDisplay = true
    }

    func enterCropMode() {
        guard let doc else { return }
        cropMode = true
        // Everything selected by default (v1.2.2 behavior).
        cropDraft = doc.viewRect.cgRect
        select(nil)
        owner?.canvasSizeChanged()
        needsDisplay = true
        onCropDraftChanged?()
    }

    func exitCropMode() {
        cropMode = false
        owner?.canvasSizeChanged()
        needsDisplay = true
    }

    func setCropDraft(_ r: CGRect) {
        cropDraft = r
        needsDisplay = true
    }

    // MARK: - Cursors

    override func resetCursorRects() {
        let cursor: NSCursor = switch tool {
        case .select: .arrow
        case .text: .iBeam
        default: .crosshair
        }
        addCursorRect(bounds, cursor: cropMode ? .arrow : cursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        guard cropMode, drag == .none else { return }
        let p = convert(event.locationInWindow, from: nil)
        if hitCropHandle(p) >= 0 { NSCursor.crosshair.set() } else if cropDraft.contains(toDoc(p)) { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
    }

    // MARK: - Input

    override func mouseDown(with event: NSEvent) {
        guard doc != nil, let owner else { return }
        window?.makeFirstResponder(self)
        owner.commitTextEdit()

        let pt = convert(event.locationInWindow, from: nil)
        let d = toDoc(pt)
        dragStartDoc = d
        undoPushed = false

        if cropMode {
            handleIndex = hitCropHandle(pt)
            if handleIndex >= 0 {
                drag = .cropHandle
            } else if cropDraft.contains(d) {
                drag = .cropMove
                cropStart = cropDraft
            } else {
                drag = .none
            }
            return
        }

        switch tool {
        case .select:
            if let sel = selected {
                let h = hitHandle(sel, pt)
                if h >= 0 {
                    drag = .handle
                    handleIndex = h
                    return
                }
            }
            let hit = topmostHit(d)
            select(hit)
            if let hit {
                if event.clickCount == 2, let t = hit as? TextAnnotation {
                    owner.beginTextEdit(t, isNew: false)
                    drag = .none
                    return
                }
                drag = .move
            }

        case .text:
            owner.handleTextToolClick(d)
        case .stamp:
            owner.placeStamp(d)
        case .sticker:
            owner.placeSticker(d)
        case .image, .crop:
            break // handled by window chrome

        case .pen, .highlight:
            if let pen = owner.makeDraft(tool, d) as? PenAnnotation {
                pen.points.append(d)
                draft = pen
                drag = .create
            }

        default: // arrow, line, rectangle, ellipse, obscure, spotlight
            draft = owner.makeDraft(tool, d)
            drag = draft != nil ? .create : .none
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let doc else { return }
        let pt = convert(event.locationInWindow, from: nil)
        let d = toDoc(pt)
        let shift = event.modifierFlags.contains(.shift)

        switch drag {
        case .create:
            if let pen = draft as? PenAnnotation {
                if let last = pen.points.last, (d - last).length <= 1.2 { return }
                pen.points.append(d)
            } else if let tp = draft as? TwoPointAnnotation {
                tp.b = shift ? Self.snapAngle(tp.a, d) : d
            } else if let ra = draft as? RectAnnotation {
                ra.b = shift ? Self.snapSquare(ra.a, d) : d
            }

        case .move:
            guard let sel = selected else { return }
            ensureUndo()
            sel.move(by: d - dragStartDoc)
            dragStartDoc = d
            doc.dirty = true

        case .handle:
            guard let sel = selected else { return }
            ensureUndo()
            sel.moveHandle(handleIndex, to: d)
            doc.dirty = true

        case .cropHandle:
            moveCropHandle(handleIndex, d)
            onCropDraftChanged?()

        case .cropMove:
            let delta = d - dragStartDoc
            var r = cropStart.offsetBy(dx: delta.dx, dy: delta.dy)
            r.origin.x = clamp(r.origin.x, 0, max(0, CGFloat(doc.width) - r.width))
            r.origin.y = clamp(r.origin.y, 0, max(0, CGFloat(doc.height) - r.height))
            cropDraft = r
            onCropDraftChanged?()

        case .none:
            return
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if drag == .create, let draft, let doc {
            let valid: Bool = switch draft {
            case let p as PenAnnotation: p.points.count >= 2 && (p.bounds.width > 2 || p.bounds.height > 2)
            case let tp as TwoPointAnnotation: (tp.b - tp.a).length >= 4
            case let ra as RectAnnotation: ra.rect.width >= 4 && ra.rect.height >= 4
            default: true
            }
            // The tool stays armed (Skitch flow).
            if valid { doc.add(draft) }
            self.draft = nil
        }
        if drag == .move || drag == .handle, undoPushed { doc?.notifyChanged() }
        drag = .none
        handleIndex = -1
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            owner?.nudgeZoom(event.scrollingDeltaY > 0 ? 1.15 : 1 / 1.15)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: owner?.escapePressed()                           // Esc
        case 36, 76: if cropMode { owner?.exitCrop(apply: true) } // Return / Enter
        case 51, 117:                                              // Delete / Forward Delete
            if selected != nil { owner?.deleteSelection(nil) }
        default: super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        owner?.commitTextEdit()
        return owner?.canvasContextMenu()
    }

    private func ensureUndo() {
        if undoPushed { return }
        doc?.pushUndo()
        undoPushed = true
    }

    private static func snapAngle(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let v = b - a
        let ang = atan2(v.dy, v.dx)
        let snap = (ang / (.pi / 4)).rounded() * (.pi / 4)
        return a + CGVector(dx: cos(snap), dy: sin(snap)) * v.length
    }

    private static func snapSquare(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let s = max(abs(b.x - a.x), abs(b.y - a.y))
        func sign(_ v: CGFloat) -> CGFloat { v > 0 ? 1 : (v < 0 ? -1 : 0) }
        return CGPoint(x: a.x + sign(b.x - a.x) * s, y: a.y + sign(b.y - a.y) * s)
    }

    private func topmostHit(_ d: CGPoint) -> Annotation? {
        doc?.annotations.last { $0.hitTest(d) }
    }

    private func hitHandle(_ a: Annotation, _ p: CGPoint) -> Int {
        for (i, h) in a.handles().enumerated() where (toView(h) - p).length <= Self.handleHit { return i }
        return -1
    }

    // MARK: - Crop dragging

    private func cropHandles() -> [CGPoint] { RectAnnotation.handles(of: cropDraft) }

    private func hitCropHandle(_ p: CGPoint) -> Int {
        for (i, h) in cropHandles().enumerated() where (toView(h) - p).length <= Self.handleHit + 2 { return i }
        return -1
    }

    private func moveCropHandle(_ index: Int, _ point: CGPoint) {
        guard let doc, let owner else { return }
        let W = CGFloat(doc.width), H = CGFloat(doc.height)
        let p = CGPoint(x: clamp(point.x, 0, W), y: clamp(point.y, 0, H))
        var left = cropDraft.minX, top = cropDraft.minY, right = cropDraft.maxX, bottom = cropDraft.maxY
        switch index {
        case 0: left = p.x; top = p.y
        case 1: right = p.x; top = p.y
        case 2: right = p.x; bottom = p.y
        case 3: left = p.x; bottom = p.y
        case 4: top = p.y
        case 5: right = p.x
        case 6: bottom = p.y
        case 7: left = p.x
        default: break
        }
        let ratio = owner.cropAspectRatio
        if ratio > 0 {
            if index < 4 {
                // Corners: width drives; clamp the derived height to the space on the
                // anchored side and pull the dragged edge back so the ratio survives.
                var w = abs(right - left)
                var h = w / ratio
                let availH = index == 0 || index == 1 ? bottom : H - top
                if h > availH {
                    h = max(1, availH)
                    w = h * ratio
                    let sx: CGFloat = right >= left ? 1 : -1
                    if index == 1 || index == 2 { right = left + sx * w } else { left = right - sx * w }
                }
                if index == 0 || index == 1 { top = bottom - h } else { bottom = top + h }
            } else if index == 5 || index == 7 {
                // Vertical edges: width drives, symmetric about the vertical center.
                var w = abs(right - left)
                var h = w / ratio
                let cy = (top + bottom) / 2
                let maxH = max(1, min(cy, H - cy) * 2)
                if h > maxH {
                    h = maxH
                    w = h * ratio
                    if index == 5 { right = left + w } else { left = right - w }
                }
                top = cy - h / 2
                bottom = cy + h / 2
            } else {
                // Horizontal edges: height drives, symmetric about the horizontal center.
                var h = abs(bottom - top)
                var w = h * ratio
                let cx = (left + right) / 2
                let maxW = max(1, min(cx, W - cx) * 2)
                if w > maxW {
                    w = maxW
                    h = w / ratio
                    if index == 6 { bottom = top + h } else { top = bottom - h }
                }
                left = cx - w / 2
                right = cx + w / 2
            }
        }
        // Never let the preview extend past the document — Apply must crop what was shown.
        let draft = CGRect(x: min(left, right), y: min(top, bottom), width: abs(right - left), height: abs(bottom - top))
            .intersection(CGRect(x: 0, y: 0, width: W, height: H))
        if draft.isNull || draft.width < 1 || draft.height < 1 { return }
        cropDraft = draft
    }

    // MARK: - Rendering

    override func draw(_ dirtyRect: NSRect) {
        guard let doc, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let v = view
        let s = pointsPerDoc

        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: CGFloat(-v.x), y: CGFloat(-v.y))
        ctx.clip(to: v.cgRect)
        Renderer.draw(ctx, doc, forExport: false, spotlightDim: AppController.shared.settings.spotlightDim, skip: editingText)
        draft?.render(ctx, RenderContext(base: doc.base, baseVersion: doc.baseVersion))
        ctx.restoreGState()

        // Screen-space chrome (constant size regardless of zoom).
        if cropMode {
            drawCropChrome(ctx)
        } else if let sel = selected, sel !== editingText {
            drawSelection(ctx, sel)
        }
    }

    private func drawSelection(_ ctx: CGContext, _ a: Annotation) {
        let b = toView(a.bounds)
        ctx.saveGState()
        ctx.setStrokeColor(RGBAColor(0xFF, 0x33, 0x66, 0xC8).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [2, 2])
        ctx.stroke(b.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()
        for h in a.handles() { drawHandle(ctx, toView(h)) }
    }

    private func drawCropChrome(_ ctx: CGContext) {
        let full = bounds
        let sel = toView(cropDraft)
        ctx.saveGState()
        ctx.addRect(full)
        ctx.addRect(sel)
        ctx.setFillColor(CGColor(gray: 0, alpha: 0x8C / 255.0))
        ctx.fillPath(using: .evenOdd)

        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0x99 / 255.0))
        ctx.setLineWidth(1)
        ctx.stroke(sel)
        // Rule-of-thirds grid.
        for i in 1...2 {
            let x = sel.minX + sel.width * CGFloat(i) / 3
            let y = sel.minY + sel.height * CGFloat(i) / 3
            ctx.strokeLineSegments(between: [CGPoint(x: x, y: sel.minY), CGPoint(x: x, y: sel.maxY),
                                             CGPoint(x: sel.minX, y: y), CGPoint(x: sel.maxX, y: y)])
        }
        ctx.restoreGState()
        for h in cropHandles() { drawHandle(ctx, toView(h)) }
    }

    private func drawHandle(_ ctx: CGContext, _ c: CGPoint) {
        let r = CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(r)
        ctx.setStrokeColor(RGBAColor.pink.cgColor)
        ctx.setLineWidth(1.4)
        ctx.stroke(r)
    }
}
