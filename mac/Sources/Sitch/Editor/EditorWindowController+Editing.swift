import AppKit
import ImageIO
import SitchCore
import UniformTypeIdentifiers

/// Annotation creation, in-place text editing and crop mode (EditorWindow.xaml.cs).
extension EditorWindowController: NSTextViewDelegate, NSTextFieldDelegate {
    // MARK: - Annotation creation

    func makeDraft(_ tool: ToolKind, _ p: CGPoint) -> Annotation? {
        let s = AppController.shared.settings
        let a: Annotation
        switch tool {
        case .arrow:
            let ar = ArrowAnnotation()
            ar.style = arrowStyle; ar.doubleHeaded = arrowDouble; ar.strokeWidth = CGFloat(s.arrowWidth)
            a = ar
        case .line:
            a = LineAnnotation(); a.strokeWidth = CGFloat(s.shapeWidth)
        case .rectangle, .ellipse:
            let b = BoxAnnotation()
            b.isEllipse = tool == .ellipse; b.filled = shapeFilled; b.strokeWidth = CGFloat(s.shapeWidth)
            a = b
        case .obscure:
            let o = ObscureAnnotation(); o.style = obscureStyle
            a = o
        case .spotlight:
            a = SpotlightAnnotation()
        case .pen:
            a = PenAnnotation(); a.strokeWidth = CGFloat(s.penWidth)
        case .highlight:
            a = HighlightAnnotation(); a.strokeWidth = CGFloat(s.highlightWidth)
        default:
            return nil
        }
        // The highlighter's default is yellow: pink marker over text reads as an error.
        a.color = tool == .highlight && color == .pink ? .yellow : color
        if let tp = a as? TwoPointAnnotation { tp.a = p; tp.b = p }
        if let ra = a as? RectAnnotation { ra.a = p; ra.b = p }
        return a
    }

    func placeStamp(_ p: CGPoint) {
        let stamp = StampAnnotation()
        stamp.kind = stampKind
        stamp.center = p
        stamp.color = color
        stamp.number = doc.nextStampNumber
        doc.add(stamp)
        if stampKind == .number { doc.nextStampNumber += 1 }
    }

    func placeSticker(_ p: CGPoint) {
        let sticker = StickerAnnotation()
        sticker.emoji = emoji
        sticker.center = p
        doc.add(sticker)
    }

    @objc func insertImage(_ sender: Any?) {
        commitTextEdit()
        // Image is a one-shot command, not a mode: the rail returns to Select (Windows parity).
        defer { selectTool(.select) }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard let window, panel.runModal() == .OK, let url = panel.url else { return }
        guard let img = Self.loadImage(url) else {
            let alert = NSAlert()
            alert.messageText = "Couldn't insert image."
            alert.informativeText = url.lastPathComponent
            alert.beginSheetModal(for: window)
            return
        }
        let view = doc.viewRect
        let scale = min(1, min(CGFloat(view.width) * 0.5 / CGFloat(img.width), CGFloat(view.height) * 0.5 / CGFloat(img.height)))
        let w = CGFloat(img.width) * scale, h = CGFloat(img.height) * scale
        let cx = CGFloat(view.x) + CGFloat(view.width) / 2, cy = CGFloat(view.y) + CGFloat(view.height) / 2
        let ann = ImageAnnotation()
        ann.source = img
        ann.a = CGPoint(x: cx - w / 2, y: cy - h / 2)
        ann.b = CGPoint(x: cx + w / 2, y: cy + h / 2)
        doc.add(ann)
        DispatchQueue.main.async { [weak self] in self?.canvas.select(ann) }
    }

    /// Decodes an image file with its EXIF orientation applied.
    static func loadImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0, h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h, 1),
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    // MARK: - Text editing

    func handleTextToolClick(_ p: CGPoint) {
        // Clicking an existing text with the Text tool edits it instead of stacking a new one (v1.4.1).
        if let existing = doc.annotations.last(where: { ($0 as? TextAnnotation)?.hitTest(p) == true }) as? TextAnnotation {
            beginTextEdit(existing, isNew: false)
            return
        }
        let t = TextAnnotation()
        t.position = p
        t.color = color
        t.fontFamily = fontFamily
        t.fontSize = fontSize
        t.bold = bold
        t.italic = italic
        beginTextEdit(t, isNew: true)
    }

    func beginTextEdit(_ t: TextAnnotation, isNew: Bool) {
        commitTextEdit()
        editing = t
        editingIsNew = isNew
        canvas.editingText = t
        canvas.select(nil)

        let tv = NSTextView(frame: .zero)
        tv.delegate = self
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: 100_000, height: 100_000)
        tv.maxSize = NSSize(width: 100_000, height: 100_000)
        tv.wantsLayer = true
        tv.layer?.borderWidth = 1
        tv.layer?.borderColor = RGBAColor.pink.cgColor
        tv.string = t.text
        editView = tv
        container.addSubview(tv)
        restyleEditView()
        positionEditView()
        window?.makeFirstResponder(tv)
        tv.selectAll(nil)

        // Surface this text's style in the bar for restyling without switching tools.
        syncTextBar(t)
        textPanel.isHidden = false
        canvas.needsDisplay = true
    }

    /// Applies the current font/color/zoom to the live editor (mid-edit restyle).
    func restyleEditView() {
        guard let tv = editView, let t = editing else { return }
        t.fontFamily = fontFamily
        t.fontSize = fontSize
        t.bold = bold
        t.italic = italic
        t.color = color
        tv.font = TextLayout.font(family: fontFamily, size: fontSize * canvas.pointsPerDoc, bold: bold, italic: italic)
        tv.textColor = color.nsColor
        tv.insertionPointColor = color.nsColor
        tv.typingAttributes = [.font: tv.font!, .foregroundColor: color.nsColor]
        sizeEditView()
        if window?.firstResponder !== tv { window?.makeFirstResponder(tv) }
    }

    func positionEditView() {
        guard let tv = editView, let t = editing else { return }
        let p = canvas.toView(t.position)
        tv.setFrameOrigin(NSPoint(x: canvas.frame.minX + p.x, y: canvas.frame.minY + p.y))
    }

    private func sizeEditView() {
        guard let tv = editView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).size
        let lineH = (tv.font.map { lm.defaultLineHeight(for: $0) }) ?? 20
        tv.setFrameSize(NSSize(width: max(24, ceil(used.width) + 4), height: max(lineH, ceil(used.height))))
    }

    func textDidChange(_ notification: Notification) {
        if (notification.object as? NSTextView) === editView { sizeEditView() }
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard textView === editView else { return false }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                commitTextEdit()
                window?.makeFirstResponder(canvas)
            }
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            cancelTextEdit()
            return true
        }
        return false
    }

    func textDidEndEditing(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView, tv === editView else { return }
        // Focus moving into the font size box is a mid-edit restyle, not a commit.
        DispatchQueue.main.async { [weak self] in
            guard let self, editView === tv else { return }
            if let fr = window?.firstResponder as? NSTextView, fr.delegate === fontSizeCombo { return }
            if window?.firstResponder === tv { return }
            commitTextEdit()
        }
    }

    func commitTextEdit() {
        guard let t = editing else { return }
        let text = (editView?.string ?? "").trimmingCharacters(in: .newlines)
        editing = nil
        hideEditView()

        var kept = false
        if editingIsNew {
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                t.text = text
                doc.add(t)
                kept = true
            }
        } else if text != t.text {
            doc.pushUndo()
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                doc.annotations.removeAll { $0 === t } // clearing removes it — and that's undoable
            } else {
                t.text = text
                kept = true
            }
            doc.dirty = true
            doc.notifyChanged()
        } else {
            kept = doc.annotations.contains { $0 === t }
        }
        canvas.editingText = nil
        // Select the committed text so an in-flight toolbar click (which triggered this
        // commit) restyles it instead of vanishing into a no-op.
        if kept { canvas.select(t) }
        canvas.needsDisplay = true
    }

    func cancelTextEdit() {
        editing = nil
        canvas.editingText = nil
        hideEditView()
        canvas.needsDisplay = true
        window?.makeFirstResponder(canvas)
    }

    private func hideEditView() {
        let tv = editView
        editView = nil
        tv?.delegate = nil
        tv?.removeFromSuperview()
        if tool != .text && !(canvas.selected is TextAnnotation) { textPanel.isHidden = true }
    }

    // MARK: - Crop

    func enterCrop() {
        commitTextEdit()
        guard !canvas.cropMode else { return }
        canvas.enterCropMode()
        normalBar.isHidden = true
        settingsHost.isHidden = true
        cropBar.isHidden = false
        aspectPopup.selectItem(at: 0)
        cropAspectRatio = 0
        lockToggle.isChecked = false
        syncCropFieldsFromDraft()
        fitZoom()
        window?.makeFirstResponder(canvas)
    }

    func exitCrop(apply: Bool) {
        guard canvas.cropMode else { return }
        if apply {
            let r = canvas.cropDraft
            doc.applyCrop(PixelRect(x: Int(r.minX.rounded()), y: Int(r.minY.rounded()),
                                    width: Int(r.width.rounded()), height: Int(r.height.rounded())))
        }
        canvas.exitCropMode()
        cropBar.isHidden = true
        normalBar.isHidden = false
        settingsHost.isHidden = false
        let back: ToolKind = tool == .crop || tool == .image ? .select : tool
        setRailChecked(back)
        canvas.setTool(back)
        fitZoom()
        updateBottom()
        window?.makeFirstResponder(canvas)
    }

    func syncCropFieldsFromDraft() {
        syncingCrop = true
        cropWField.stringValue = String(Int(canvas.cropDraft.width.rounded()))
        cropHField.stringValue = String(Int(canvas.cropDraft.height.rounded()))
        syncingCrop = false
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === cropWField { cropFieldEdited(widthEdited: true) } else if field === cropHField { cropFieldEdited(widthEdited: false) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === cropWField || control === cropHField else { return false }
        if selector == #selector(NSResponder.insertNewline(_:)) { exitCrop(apply: true); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { exitCrop(apply: false); return true }
        return false
    }

    private func cropFieldEdited(widthEdited: Bool) {
        guard !syncingCrop, canvas.cropMode,
              var w = Int(cropWField.stringValue.trimmingCharacters(in: .whitespaces)),
              var h = Int(cropHField.stringValue.trimmingCharacters(in: .whitespaces)) else { return }
        w = clamp(w, 1, doc.width)
        h = clamp(h, 1, doc.height)

        // Honor an active aspect lock/preset: the edited field drives the other.
        if cropAspectRatio > 0 {
            if widthEdited { h = max(1, Int((CGFloat(w) / cropAspectRatio).rounded())) } else { w = max(1, Int((CGFloat(h) * cropAspectRatio).rounded())) }
            if w > doc.width { w = doc.width; h = max(1, Int((CGFloat(w) / cropAspectRatio).rounded())) }
            if h > doc.height { h = doc.height; w = max(1, Int((CGFloat(h) * cropAspectRatio).rounded())) }
            syncingCrop = true
            if widthEdited { cropHField.stringValue = String(h) } else { cropWField.stringValue = String(w) }
            syncingCrop = false
        }

        var r = canvas.cropDraft
        r.size = CGSize(width: w, height: h)
        r.origin.x = clamp(r.origin.x, 0, CGFloat(doc.width - w))
        r.origin.y = clamp(r.origin.y, 0, CGFloat(doc.height - h))
        canvas.setCropDraft(r)
    }

    @objc func aspectChanged(_ sender: NSPopUpButton) {
        let idx = max(0, sender.indexOfSelectedItem)
        let r = Self.aspectPresets[idx].1
        cropAspectRatio = r < 0 ? CGFloat(doc.width) / CGFloat(doc.height) : r
        if cropAspectRatio > 0 { reshapeCropToRatio(cropAspectRatio) }
    }

    func updateLock() {
        if lockToggle.isChecked {
            let locked = canvas.cropDraft.width / max(1, canvas.cropDraft.height)
            if cropAspectRatio <= 0 { cropAspectRatio = locked }
        } else if aspectPopup.indexOfSelectedItem == 0 {
            cropAspectRatio = 0
        }
    }

    private func reshapeCropToRatio(_ ratio: CGFloat) {
        let r = canvas.cropDraft
        let W = CGFloat(doc.width), H = CGFloat(doc.height)
        var w = r.width, h = w / ratio
        if h > H { h = H; w = h * ratio }
        if w > W { w = W; h = w / ratio }
        var nr = CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
        nr.origin.x = clamp(nr.origin.x, 0, W - w)
        nr.origin.y = clamp(nr.origin.y, 0, H - h)
        canvas.setCropDraft(nr)
        syncCropFieldsFromDraft()
    }

    /// Esc: cancels crop, otherwise drops the selection.
    func escapePressed() {
        if canvas.cropMode { exitCrop(apply: false) } else { canvas.select(nil) }
    }

    override func cancelOperation(_ sender: Any?) { escapePressed() }
}
