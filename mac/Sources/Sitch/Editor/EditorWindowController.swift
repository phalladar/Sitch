import AppKit
import SitchCore

/// One editor window = one capture (port of windows/Sitch/Editor/EditorWindow.xaml(.cs)).
/// Windows' in-window tab strip becomes native macOS window tabs: "New Capture" from inside an
/// editor opens the next capture as a tab of this window (`addTab`).
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    /// (Not `document`: NSWindowController already has one.)
    private(set) var doc: Document
    private(set) var docName: String

    let canvas = DocumentCanvas()
    var container: CanvasContainer!
    var scrollView: CanvasScrollView!

    // ---- current style state (EditorWindow.xaml.cs fields) ----
    var tool: ToolKind = .arrow
    var color: RGBAColor = .pink
    var arrowStyle: ArrowStyle = .tapered
    var arrowDouble = false
    var shapeFilled = false
    var obscureStyle: ObscureStyle = .pixelate
    var stampKind: StampKind = .check
    var emoji = "😀"
    var fontFamily = TextLayout.systemFamily
    var fontSize: CGFloat = 28
    var bold = true
    var italic = false
    var saveFormat = "png"

    /// Crop aspect constraint (0 = free); read by the canvas's handle math.
    var cropAspectRatio: CGFloat = 0
    var syncingCrop = false
    var syncingSelection = false

    // text editing overlay state
    var editing: TextAnnotation?
    var editingIsNew = false
    var editView: NSTextView?

    var tempFiles: [URL] = []
    private var closeConfirmed = false
    private var presented = false
    /// NSWindow.windowController is weak: an open editor owns itself until its window closes
    /// (WPF windows stay alive while shown), whoever else holds a reference.
    private var keepAlive: EditorWindowController?

    // ---- chrome (built in +Toolbar) ----
    var railButtons: [ToolKind: ChromeButton] = [:]
    var colorWell: ChromeButton!
    var normalBar: NSStackView!
    var cropBar: NSView!
    var settingsHost: NSView!
    var toolIcon: ChromeButton!
    var toolNameLabel: NSTextField!
    var swatchPanel: NSStackView!
    var swatchDivider: NSView!
    var widthPanel: NSStackView!
    var widthButtons: [(CGFloat, ChromeButton)] = []
    var pxField: NSTextField!
    var arrowPanel: NSStackView!
    var arrowButtons: [(ArrowStyle, ChromeButton)] = []
    var arrowDoubleButton: ChromeButton!
    var textPanel: NSStackView!
    var fontPopup: NSPopUpButton!
    var fontSizeCombo: NSComboBox!
    var boldToggle: ChromeButton!
    var italicToggle: ChromeButton!
    var fillPanel: NSStackView!
    var outlineToggle: ChromeButton!
    var filledToggle: ChromeButton!
    var obscurePanel: NSStackView!
    var obscureButtons: [(ObscureStyle, ChromeButton)] = []
    var stampPanel: NSStackView!
    var stampButtons: [(StampKind, ChromeButton)] = []
    var stickerPanel: NSStackView!
    var emojiButton: ChromeButton!
    var spotlightPanel: NSStackView!
    var cropWField: NSTextField!
    var cropHField: NSTextField!
    var aspectPopup: NSPopUpButton!
    var lockToggle: ChromeButton!

    // ---- bottom bar ----
    var undoButton: ChromeButton!
    var redoButton: ChromeButton!
    var zoomLabel: ChromeButton!
    var sizeReadout: NSTextField!
    var saveButton: ChromeButton!
    var shareButton: ChromeButton!

    static let minSize = NSSize(width: 760, height: 420)
    static let topBarHeight: CGFloat = 44, bottomBarHeight: CGFloat = 40, railWidth: CGFloat = 46

    init(image: CGImage, title: String, pointScale: CGFloat) {
        doc = Document(base: image, pointScale: pointScale)
        docName = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : title
        super.init(window: nil)
        build()
    }

    /// Used by --demo: a prepared document (annotations already placed).
    init(document: Document, title: String) {
        doc = document
        docName = title
        super.init(window: nil)
        doc.dirty = false
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Construction

    private func build() {
        let s = AppController.shared.settings
        color = RGBAColor(hex: s.defaultColor) ?? .pink
        fontFamily = s.fontFamily
        fontSize = CGFloat(s.textSize)
        obscureStyle = ObscureStyle(rawValue: s.obscureStyle.lowercased()) ?? .pixelate
        saveFormat = Exporters.formats.contains(s.defaultFormat) ? s.defaultFormat : "png"

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.contentMinSize = Self.minSize
        window.title = "\(docName) — Sitch"
        window.tabbingIdentifier = "SitchEditor"
        window.isReleasedWhenClosed = false
        window.backgroundColor = Theme.bar
        self.window = window
        window.delegate = self

        canvas.owner = self
        canvas.doc = doc
        canvas.onSelectionChanged = { [weak self] in self?.selectionChanged() }
        canvas.onCropDraftChanged = { [weak self] in self?.syncCropFieldsFromDraft() }
        doc.onChange = { [weak self] in self?.docChanged() }

        container = CanvasContainer(canvas: canvas)
        scrollView = CanvasScrollView(frame: .zero)
        scrollView.documentView = container
        scrollView.onZoom = { [weak self] f in self?.nudgeZoom(f) }

        let root = NSView()
        let top = buildTopBar()
        let rail = buildRail()
        let bottom = buildBottomBar()
        for v in [top, rail, bottom, scrollView!] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: root.topAnchor),
            top.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            top.heightAnchor.constraint(equalToConstant: Self.topBarHeight),

            bottom.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            bottom.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bottom.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),

            rail.topAnchor.constraint(equalTo: top.bottomAnchor),
            rail.bottomAnchor.constraint(equalTo: bottom.topAnchor),
            rail.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            rail.widthAnchor.constraint(equalToConstant: Self.railWidth),

            scrollView.topAnchor.constraint(equalTo: top.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottom.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: rail.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        window.contentView = root

        let last = ToolKind(rawValue: s.lastTool.lowercased())
        let start = s.rememberLastTool && last != nil && last != .crop && last != .image ? last! : .arrow
        selectTool(start)
        updateBottom()
    }

    // MARK: - Presenting & sizing

    /// Size/position (on the display `sourceRect` came from, global top-left points), show, activate.
    func present(sourceRect: CGRect?) {
        guard let window else { return }
        let screen = Self.screen(for: sourceRect) ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let scale = screen?.backingScaleFactor ?? 2
        canvas.setBackingScale(scale)

        let s = AppController.shared.settings
        var fit = false
        var content: NSSize
        // Returning users get the window size they last closed with; the capture scales to
        // fit inside it — or shows at 100% if it fits.
        if s.editorWidth >= Self.minSize.width && s.editorHeight >= Self.minSize.height {
            content = NSSize(width: min(s.editorWidth, visible.width * 0.98), height: min(s.editorHeight, visible.height * 0.98))
            fit = true
        } else {
            // First-ever editor: sized to the capture at 100% when it fits (v1.4.0 parity).
            let v = doc.viewRect
            let chromeW = Self.railWidth + CanvasContainer.margin * 2 + 2
            let chromeH = Self.topBarHeight + Self.bottomBarHeight + CanvasContainer.margin * 2 + 2
            let docW = CGFloat(v.width) / scale, docH = CGFloat(v.height) / scale
            let titlebar: CGFloat = 28
            if docW + chromeW < visible.width * 0.95 && docH + chromeH + titlebar < visible.height * 0.95 {
                content = NSSize(width: max(Self.minSize.width, docW + chromeW), height: max(Self.minSize.height, docH + chromeH))
                canvas.setZoom(1)
            } else {
                content = NSSize(width: visible.width * 0.85, height: visible.height * 0.85 - titlebar)
                fit = true
            }
        }
        window.setContentSize(content)
        let f = window.frame
        window.setFrameOrigin(NSPoint(x: visible.midX - f.width / 2, y: visible.midY - f.height / 2))
        if fit { chooseZoomForViewport() } else { canvasSizeChanged() }

        presented = true
        keepAlive = self
        AppController.shared.editorDidOpen(self)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        NSApp.activate()
    }

    /// The screen containing `rect`'s center; `rect` is global top-left-origin points.
    static func screen(for rect: CGRect?) -> NSScreen? {
        guard let rect, let primary = NSScreen.screens.first else { return nil }
        let p = NSPoint(x: rect.midX, y: primary.frame.maxY - rect.midY)
        return NSScreen.screens.first { $0.frame.contains(p) }
    }

    /// Opens `editor` as a native tab of this window (New Capture from inside an editor).
    func addTab(_ editor: EditorWindowController) {
        guard let window, let other = editor.window else { return }
        editor.canvas.setBackingScale(window.backingScaleFactor)
        other.setFrame(window.frame, display: false)
        window.addTabbedWindow(other, ordered: .above)
        editor.presented = true
        editor.keepAlive = editor
        AppController.shared.editorDidOpen(editor)
        other.makeKeyAndOrderFront(nil)
        editor.chooseZoomForViewport()
        other.makeFirstResponder(editor.canvas)
        NSApp.activate()
    }

    /// Within the window: 100% when the capture fits, otherwise zoom-to-fit.
    func chooseZoomForViewport() {
        window?.contentView?.layoutSubtreeIfNeeded()
        let v = doc.viewRect
        let avail = availableDevicePixels()
        if CGFloat(v.width) <= avail.width && CGFloat(v.height) <= avail.height { canvas.setZoom(1) } else { fitZoom() }
    }

    /// Viewport size in device pixels, minus the canvas margins.
    private func availableDevicePixels() -> CGSize {
        let clip = scrollView.contentView.bounds.size
        let m = CanvasContainer.margin * 2 + 2
        let scale = canvas.backingScale
        return CGSize(width: max(80, clip.width - m) * scale, height: max(80, clip.height - m) * scale)
    }

    func fitZoom() {
        window?.contentView?.layoutSubtreeIfNeeded()
        let v = canvas.cropMode ? PixelRect(x: 0, y: 0, width: doc.width, height: doc.height) : doc.viewRect
        let avail = availableDevicePixels()
        canvas.setZoom(min(1, min(avail.width / CGFloat(v.width), avail.height / CGFloat(v.height))))
    }

    func nudgeZoom(_ factor: CGFloat) { canvas.setZoom(canvas.zoom * factor) }

    /// Canvas size changed (zoom, crop, rotate): resize the scroll document.
    func canvasSizeChanged() {
        container?.layoutCanvas()
        positionEditView()
    }

    func zoomChanged() {
        zoomLabel?.content = .menuLabel(nil, "\(Int((canvas.zoom * 100).rounded()))%", .systemFont(ofSize: 13))
        // The overlay is positioned/scaled for one specific zoom — end the session rather than
        // leave it floating at a stale position.
        if editing != nil { commitTextEdit() }
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        guard let window else { return }
        if editing != nil { commitTextEdit() }
        canvas.setBackingScale(window.backingScaleFactor)
    }

    // MARK: - Document changes

    func docChanged() {
        // Undo/redo restores clones — drop a selection that points at a detached ghost.
        if let sel = canvas.selected, !doc.annotations.contains(where: { $0 === sel }) { canvas.select(nil) }
        canvasSizeChanged()
        canvas.needsDisplay = true
        updateBottom()
    }

    func updateBottom() {
        undoButton?.isEnabled = doc.canUndo
        redoButton?.isEnabled = doc.canRedo
        let v = doc.viewRect
        sizeReadout?.stringValue = "\(v.width) × \(v.height) px"
        zoomChanged()
    }

    // MARK: - Close / save prompt

    /// Unsaved, non-pristine changes.
    var needsSavePrompt: Bool { doc.dirty && !doc.isPristine }

    /// Save prompt; false means the user cancelled the close.
    func confirmClose() -> Bool {
        commitTextEdit()
        // Crop/rotate/flip count as changes too; a fully undone doc counts as pristine.
        guard needsSavePrompt else { return true }
        window?.makeKeyAndOrderFront(nil)
        let alert = NSAlert()
        alert.messageText = "“\(docName)” has unsaved changes. Save before closing?"
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveAs()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    /// Close after the caller already ran confirmClose (quit flow).
    func closeWithoutPrompt() {
        closeConfirmed = true
        window?.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closeConfirmed { return true }
        if confirmClose() { closeConfirmed = true; return true }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        commitTextEdit()
        rememberWindowSize()
        TempFiles.remove(tempFiles)
        tempFiles.removeAll()
        if presented { AppController.shared.editorDidClose(self) }
        presented = false
        // Release on the next turn so AppKit finishes the close with us still alive.
        DispatchQueue.main.async { [self] in keepAlive = nil }
    }

    /// The next editor opens with the dimensions this one closes with.
    private func rememberWindowSize() {
        guard let window, !window.isMiniaturized else { return }
        let size = window.contentLayoutRect.size
        guard size.width >= Self.minSize.width, size.height >= Self.minSize.height else { return }
        AppController.shared.settings.editorWidth = size.width
        AppController.shared.settings.editorHeight = size.height
        AppController.shared.saveSettings()
    }

    /// --demo-crop: open straight into crop mode.
    func enterCropMode() { selectTool(.crop) }
}
