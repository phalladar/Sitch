import CoreGraphics

public enum RotateFlipKind: Sendable { case rotateLeft, rotateRight, flipHorizontal, flipVertical }

/// One editing document: an immutable pristine capture + an ordered list of annotation
/// objects + a non-destructive crop. Undo/redo is whole-state snapshots (simple and correct;
/// per-op commands can come later).
public final class Document {
    private struct State {
        var base: CGImage
        var baseVersion: Int
        var annotations: [Annotation]
        var crop: PixelRect?
        var nextStampNumber: Int
    }

    private var undoStack: [State] = []
    private var redoStack: [State] = []
    private static let maxUndo = 100

    public private(set) var base: CGImage
    public private(set) var baseVersion = 0
    public var annotations: [Annotation] = []
    public private(set) var crop: PixelRect?
    public var nextStampNumber = 1
    public var dirty = false
    /// Capture pixels per point (2 on Retina). Exports use it so a PDF page or a pasted image
    /// comes out at the size it had on screen; 1 for images opened from disk.
    public let pointScale: CGFloat

    /// Fired after every mutation (including undo/redo).
    public var onChange: (() -> Void)?

    public init(base: CGImage, pointScale: CGFloat = 1) {
        self.base = base
        self.pointScale = max(1, pointScale)
    }

    public var width: Int { base.width }
    public var height: Int { base.height }

    /// The visible viewport (crop applied), in doc pixels.
    public var viewRect: PixelRect { crop ?? PixelRect(x: 0, y: 0, width: width, height: height) }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Untouched or fully undone — closing it needs no save prompt.
    public var isPristine: Bool { annotations.isEmpty && crop == nil && baseVersion == 0 }

    public func notifyChanged() { onChange?() }

    /// Take an undo snapshot BEFORE a mutation (add/delete/move/crop/rotate…).
    public func pushUndo() {
        undoStack.append(snapshot())
        if undoStack.count > Self.maxUndo { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    public func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        restore(s)
    }

    public func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        restore(s)
    }

    private func snapshot() -> State {
        State(base: base, baseVersion: baseVersion, annotations: annotations.map { $0.clone() },
              crop: crop, nextStampNumber: nextStampNumber)
    }

    private func restore(_ s: State) {
        base = s.base
        baseVersion = s.baseVersion
        annotations = s.annotations.map { $0.clone() }
        crop = s.crop
        nextStampNumber = s.nextStampNumber
        dirty = true
        notifyChanged()
    }

    // MARK: - Mutations

    public func add(_ a: Annotation) {
        pushUndo()
        annotations.append(a)
        dirty = true
        notifyChanged()
    }

    public func remove(_ a: Annotation) {
        pushUndo()
        annotations.removeAll { $0 === a }
        dirty = true
        notifyChanged()
    }

    public func applyCrop(_ rect: PixelRect) {
        pushUndo()
        var r = rect
        r.x = clamp(r.x, 0, max(0, width - 1))
        r.y = clamp(r.y, 0, max(0, height - 1))
        r.width = clamp(r.width, 1, width - r.x)
        r.height = clamp(r.height, 1, height - r.y)
        crop = r.width >= width && r.height >= height ? nil : r
        dirty = true
        notifyChanged()
    }

    public func rotateFlip(_ kind: RotateFlipKind) {
        let w = CGFloat(width), h = CGFloat(height)
        let swap = kind == .rotateLeft || kind == .rotateRight
        // Annotations follow the image (spec: "Rotate left/right and flip — annotations follow").
        let map: (CGPoint) -> CGPoint
        let t: CGAffineTransform
        switch kind {
        case .rotateLeft:
            map = { CGPoint(x: $0.y, y: w - $0.x) }
            t = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        case .rotateRight:
            map = { CGPoint(x: h - $0.y, y: $0.x) }
            t = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        case .flipHorizontal:
            map = { CGPoint(x: w - $0.x, y: $0.y) }
            t = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
        case .flipVertical:
            map = { CGPoint(x: $0.x, y: h - $0.y) }
            t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        }
        let newW = swap ? height : width, newH = swap ? width : height
        guard let ctx = Draw.makeContext(width: newW, height: newH, colorSpace: Draw.colorSpace(for: base)) else { return }
        ctx.concatenate(t) // old doc coords → new doc coords (both top-left origin)
        Draw.image(base, in: CGRect(x: 0, y: 0, width: w, height: h), ctx)
        guard let rotated = ctx.makeImage() else { return }

        pushUndo()
        base = rotated
        baseVersion += 1
        for a in annotations { a.applyTransform(map) }
        if let c = crop {
            let r = CGRect(corner: map(CGPoint(x: c.x, y: c.y)), map(CGPoint(x: c.x + c.width, y: c.y + c.height)))
            crop = PixelRect(x: Int(r.minX), y: Int(r.minY), width: Int(r.width), height: Int(r.height))
        }
        dirty = true
        notifyChanged()
    }
}
