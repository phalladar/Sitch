import AppKit
import SitchCore

/// One borderless overlay per display showing that display's slice of the frozen desktop
/// (Windows OverlayWindow parity). It draws in local top-left points but reports every pointer
/// position to the controller in global Quartz points, so selection math lives in one space.
@MainActor
final class OverlayWindow: NSWindow {
    let display: DisplayGeometry

    init(controller: CaptureController, display: DisplayGeometry, frozen: CGImage?) {
        self.display = display
        super.init(contentRect: ScreenSpace.toAppKit(display.frame), styleMask: .borderless,
                   backing: .buffered, defer: false)
        // Above the menu bar and Dock, on every Space, over full-screen apps.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        contentView = OverlayView(controller: controller, display: display, frozen: frozen)
        setFrame(ScreenSpace.toAppKit(display.frame), display: false)
    }

    // Borderless windows refuse key status by default; the one under the cursor needs Esc/arrows.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func repaint() { contentView?.needsDisplay = true }
}

@MainActor
private final class OverlayView: NSView {
    private unowned let controller: CaptureController
    private let display: DisplayGeometry
    private let frozen: CGImage?

    init(controller: CaptureController, display: DisplayGeometry, frozen: CGImage?) {
        self.controller = controller
        self.display = display
        self.frozen = frozen
        super.init(frame: NSRect(origin: .zero, size: display.frame.size))
        // activeAlways: overlays that aren't key (other displays) still track the pointer.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var cursor: NSCursor { controller.mode == .region ? .crosshair : .arrow }
    override func cursorUpdate(with event: NSEvent) { cursor.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }

    /// The pointer in global Quartz points (event locations are per-window; this is not).
    private var pointer: CGPoint { ScreenSpace.toQuartz(NSEvent.mouseLocation) }

    // MARK: - Input

    override func mouseMoved(with event: NSEvent) {
        cursor.set()
        controller.updatePointer(pointer)
    }

    override func mouseDown(with event: NSEvent) {
        if controller.mode == .region { controller.beginDrag(pointer, on: display) }
    }

    override func mouseDragged(with event: NSEvent) { controller.updatePointer(pointer) }
    override func mouseUp(with event: NSEvent) { controller.endDrag(pointer) }
    override func rightMouseDown(with event: NSEvent) { controller.cancel() }

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        // ⌥ for 10-pt steps: Ctrl+arrows belong to Mission Control / Spaces.
        let step: CGFloat = event.modifierFlags.contains(.option) ? 10 : 1
        switch event.keyCode {
        case 53: controller.cancel()                                 // Esc abandons the whole capture
        case 36, 76: controller.confirmSelection()                   // Return / Enter
        case 123: controller.nudgeSelection(-step, 0, resize: shift)  // ←
        case 124: controller.nudgeSelection(step, 0, resize: shift)   // →
        case 126: controller.nudgeSelection(0, -step, resize: shift)  // ↑
        case 125: controller.nudgeSelection(0, step, resize: shift)   // ↓
        default: super.keyDown(with: event)
        }
    }

    // MARK: - Painting

    private func local(_ r: CGRect) -> CGRect { r.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let full = bounds
        if let frozen {
            ctx.interpolationQuality = .none // 1:1 with the display's own pixels
            Draw.image(frozen, in: full, ctx)
        } else {
            ctx.setFillColor(.black)
            ctx.fill(full)
        }

        let dim = CGColor(gray: 0, alpha: 0x73 / 255.0)
        guard let selGlobal = controller.highlightRect else {
            ctx.setFillColor(dim)
            ctx.fill(full)
            if controller.mode == .region { drawCrosshair(ctx) }
            return
        }

        let sel = local(selGlobal)
        ctx.saveGState()
        ctx.addRect(full)
        ctx.addRect(sel)
        ctx.setFillColor(dim)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        ctx.setStrokeColor(RGBAColor.pink.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(sel)

        // Only annotate the readout on overlays the selection actually touches.
        if sel.intersects(full), let size = controller.resultPixelSize(of: selGlobal) {
            drawReadout(ctx, full: full, sel: sel, text: "\(size.width) × \(size.height)")
        }
        if controller.mode == .region && !controller.hasSelection { drawCrosshair(ctx) }
    }

    private func drawCrosshair(_ ctx: CGContext) {
        // Shared controller pointer: only the display actually containing it draws a crosshair.
        let p = controller.pointer
        guard display.frame.contains(p) else { return }
        let x = (p.x - display.frame.minX).rounded() + 0.5, y = (p.y - display.frame.minY).rounded() + 0.5
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0x80 / 255.0))
        ctx.setLineWidth(1)
        ctx.strokeLineSegments(between: [CGPoint(x: x, y: 0), CGPoint(x: x, y: bounds.height),
                                         CGPoint(x: 0, y: y), CGPoint(x: bounds.width, y: y)])
    }

    private func drawReadout(_ ctx: CGContext, full: CGRect, sel: CGRect, text: String) {
        let label = TextLayout.string(text, font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        let size = TextLayout.size(label)
        let pad: CGFloat = 5
        var x = min(sel.maxX + 8, full.width - size.width - pad * 2 - 4)
        var y = min(sel.maxY + 8, full.height - size.height - pad * 2 - 4)
        x = max(x, 4); y = max(y, 4)
        let bg = CGRect(x: x, y: y, width: size.width + pad * 2, height: size.height + pad * 2)
        ctx.addPath(CGPath(roundedRect: bg, cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.setFillColor(RGBAColor(0x1E, 0x1E, 0x20, 0xD9).cgColor)
        ctx.fillPath()
        TextLayout.draw(label, at: CGPoint(x: x + pad, y: y + pad), in: ctx)
    }
}
