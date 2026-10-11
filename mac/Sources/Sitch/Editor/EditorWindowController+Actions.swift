import AppKit
import SitchCore
import UniformTypeIdentifiers

/// Output actions, menu commands (first-responder targets wired by MainMenu) and the canvas
/// context menu.
extension EditorWindowController: NSMenuItemValidation {
    // MARK: - Output

    /// The flattened document (crop applied) at full resolution.
    func renderFinal() -> CGImage? {
        Renderer.renderToImage(doc, spotlightDim: AppController.shared.settings.spotlightDim)
    }

    func copyImage() {
        commitTextEdit()
        guard let img = renderFinal() else { return }
        Toast.show(ClipboardHelper.copy(img, pointScale: doc.pointScale) ? "Copied to clipboard." : "Clipboard is busy — try again.")
    }

    func writeTempPNG() -> URL? {
        commitTextEdit()
        guard let img = renderFinal() else { return nil }
        let stamp = Self.timeFormatter.string(from: Date())
        guard let url = try? TempFiles.writePNG(img, name: Self.safeFileName("\(docName) \(stamp)"), pointScale: doc.pointScale)
        else { return nil }
        tempFiles.append(url)
        return url
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH.mm.ss"
        return f
    }()

    static func safeFileName(_ name: String) -> String {
        String(name.map { "/:\\".contains($0) ? "_" : $0 })
    }

    func showSaveMenu() {
        let menu = NSMenu()
        for fmt in Exporters.formats {
            let item = ActionMenuItem(title: "." + fmt) { [weak self] in
                guard let self else { return }
                saveFormat = fmt
                saveButton.content = .menuLabel(ToolIcons.save, "." + fmt, .systemFont(ofSize: 13))
                saveAs()
            }
            item.state = fmt == saveFormat ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Save As…") { [weak self] in self?.saveAs() })
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: saveButton.bounds.height + 4), in: saveButton)
    }

    /// Save panel → export. True when the document was written.
    @discardableResult
    func saveAs() -> Bool {
        commitTextEdit()
        guard let img = renderFinal() else { return false }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(Self.safeFileName(docName)).\(saveFormat)"
        if let type = Self.contentType(saveFormat) { panel.allowedContentTypes = [type] }
        let folder = AppController.shared.settings.defaultSaveFolder
        var isDir: ObjCBool = false
        if !folder.isEmpty, FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue {
            panel.directoryURL = URL(fileURLWithPath: folder)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try Exporters.save(img, to: url, pointScale: doc.pointScale)
            doc.dirty = false
            Toast.show("Saved \(url.lastPathComponent)")
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Save failed."
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }
    }

    static func contentType(_ fmt: String) -> UTType? {
        switch fmt {
        case "png": .png
        case "jpg": .jpeg
        case "pdf": .pdf
        case "tiff": .tiff
        default: nil
        }
    }

    func trashClicked() {
        commitTextEdit()
        if canvas.selected != nil { deleteSelection(nil); return }
        guard !doc.annotations.isEmpty, let window else { return }
        let alert = NSAlert()
        alert.messageText = "Remove all annotations?"
        alert.addButton(withTitle: "Remove All")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            doc.pushUndo()
            doc.annotations.removeAll()
            doc.dirty = true
            doc.notifyChanged()
        }
    }

    func restack(_ direction: Int) {
        guard let sel = canvas.selected, let i = doc.annotations.firstIndex(where: { $0 === sel }) else { return }
        let j = i + direction
        guard j >= 0, j < doc.annotations.count else { return }
        doc.pushUndo()
        doc.annotations.swapAt(i, j)
        doc.dirty = true
        doc.notifyChanged()
    }

    func showZoomMenu() {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(title: "Fit") { [weak self] in self?.fitZoom() })
        for pct in [25, 50, 75, 100, 150, 200, 300] {
            menu.addItem(ActionMenuItem(title: "\(pct)%") { [weak self] in self?.canvas.setZoom(CGFloat(pct) / 100) })
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: zoomLabel.bounds.height + 4), in: zoomLabel)
    }

    func canvasContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionMenuItem(title: "Rotate Left") { [weak self] in self?.rotateLeft(nil) })
        menu.addItem(ActionMenuItem(title: "Rotate Right") { [weak self] in self?.rotateRight(nil) })
        menu.addItem(ActionMenuItem(title: "Flip Horizontal") { [weak self] in self?.flipHorizontal(nil) })
        menu.addItem(ActionMenuItem(title: "Flip Vertical") { [weak self] in self?.flipVertical(nil) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Crop") { [weak self] in self?.startCrop(nil) })
        menu.addItem(.separator())
        let hasSel = canvas.selected != nil
        for item in [
            ActionMenuItem(title: "Bring Forward") { [weak self] in self?.restack(1) },
            ActionMenuItem(title: "Send Backward") { [weak self] in self?.restack(-1) },
            ActionMenuItem(title: "Delete") { [weak self] in self?.deleteSelection(nil) },
        ] {
            item.isEnabled = hasSel
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Menu commands (first responder)

    @objc func undoEdit(_ sender: Any?) {
        guard editing == nil else { return }
        doc.undo()
    }

    @objc func redoEdit(_ sender: Any?) {
        guard editing == nil else { return }
        doc.redo()
    }

    /// ⌘C: text views / fields earlier in the responder chain handle their own copy first.
    @objc func copy(_ sender: Any?) { copyImage() }

    @objc func saveImage(_ sender: Any?) { saveAs() }

    @objc func deleteSelection(_ sender: Any?) {
        guard let sel = canvas.selected else { return }
        doc.remove(sel)
        canvas.select(nil)
    }

    @objc func zoomIn(_ sender: Any?) { nudgeZoom(1.25) }
    @objc func zoomOut(_ sender: Any?) { nudgeZoom(1 / 1.25) }
    @objc func zoomActualSize(_ sender: Any?) { canvas.setZoom(1) }
    @objc func zoomToFit(_ sender: Any?) { fitZoom() }

    @objc func rotateLeft(_ sender: Any?) { commitTextEdit(); doc.rotateFlip(.rotateLeft) }
    @objc func rotateRight(_ sender: Any?) { commitTextEdit(); doc.rotateFlip(.rotateRight) }
    @objc func flipHorizontal(_ sender: Any?) { commitTextEdit(); doc.rotateFlip(.flipHorizontal) }
    @objc func flipVertical(_ sender: Any?) { commitTextEdit(); doc.rotateFlip(.flipVertical) }
    @objc func startCrop(_ sender: Any?) { selectTool(.crop) }

    @objc func newCaptureTab(_ sender: Any?) {
        commitTextEdit()
        AppController.shared.captureRegion(into: self)
    }

    @objc func shareImage(_ sender: Any?) {
        guard let url = writeTempPNG() else { return }
        ShareHelper.share(url, from: shareButton)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undoEdit(_:)): return editing == nil && doc.canUndo
        case #selector(redoEdit(_:)): return editing == nil && doc.canRedo
        case #selector(deleteSelection(_:)): return editing == nil && canvas.selected != nil
        case #selector(rotateLeft(_:)), #selector(rotateRight(_:)), #selector(flipHorizontal(_:)),
             #selector(flipVertical(_:)), #selector(startCrop(_:)), #selector(insertImage(_:)):
            return !canvas.cropMode
        default: return true
        }
    }
}

/// Menu item that runs a closure (popup menus built on the fly).
@MainActor
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}
