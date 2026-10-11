import AppKit
import SitchCore

/// Chrome construction and tool/option state (EditorWindow.xaml + BuildRail/BuildSwatches/…,
/// UpdateToolOptions, SyncOptionStates and the style setters).
extension EditorWindowController {
    static let paletteHex = ["#FF3366", "#FF9500", "#FFD60A", "#34C759", "#2E7DF6", "#5E5CE6", "#AF52DE", "#1D1D1F", "#FFFFFF"]
    static let widthPresets: [CGFloat] = [2, 4, 8, 16, 28]
    static let fontSizes = [12, 14, 16, 20, 24, 28, 34, 40, 48, 64, 80, 96]

    // MARK: - Top bar

    func buildTopBar() -> NSView {
        let bar = BarView(divider: .bottom)
        let body = NSFont.systemFont(ofSize: 13)

        let newCapture = ChromeButton(.icon, .glyphText(ToolIcons.camera, "New Capture", body),
                                      toolTip: "New Capture (region)") { [weak self] in self?.newCaptureTab(nil) }
        toolIcon = ChromeButton(.icon, .glyph(ToolIcons.glyph(.arrow)))
        toolIcon.tint = Theme.accent
        toolIcon.padding = NSEdgeInsets()
        toolNameLabel = makeLabel("Arrow", weight: .semibold, color: Theme.accent)

        // Swatches + rainbow custom-color button.
        var swatches: [NSView] = Self.paletteHex.map { hex in
            let c = RGBAColor.hex(hex)
            let b = ChromeButton(.icon, .custom(CGSize(width: 16, height: 16)) { r, _ in Pickers.swatch(r, c) },
                                 toolTip: hex) { [weak self] in self?.setColor(c) }
            b.padding = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
            return b
        }
        let custom = ChromeButton(.icon, .custom(CGSize(width: 16, height: 16)) { r, _ in Self.drawRainbow(r) },
                                  toolTip: "Custom color…")
        custom.padding = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        custom.onClick = { [weak self, weak custom] in
            guard let self, let custom else { return }
            Pickers.showColorPicker(from: custom, current: color) { [weak self] c in self?.setColor(c) }
        }
        swatches.append(custom)
        swatchPanel = hStack(swatches)
        swatchDivider = DividerView()

        // Width presets + px field.
        widthButtons = Self.widthPresets.map { value in
            let h = clamp(value * 0.75, 2, 14), r = clamp(value * 0.35, 1, 7)
            let b = ChromeButton(.seg, .custom(CGSize(width: 18, height: 14)) { rect, fg in
                fg.setFill()
                let bar = NSRect(x: rect.minX, y: rect.midY - h / 2, width: 18, height: h)
                NSBezierPath(roundedRect: bar, xRadius: r, yRadius: r).fill()
            }, toolTip: "\(Int(value)) px") { [weak self] in self?.setWidth(value) }
            return (value, b)
        }
        pxField = NSTextField(string: "")
        pxField.alignment = .center
        pxField.font = body
        pxField.target = self
        pxField.action = #selector(pxFieldCommitted(_:))
        pxField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let pxSpacer = NSView()
        pxSpacer.widthAnchor.constraint(equalToConstant: 3).isActive = true
        widthPanel = hStack(widthButtons.map(\.1) + [spacer(6), pxField, pxSpacer, makeLabel("px", color: Theme.textDim)])

        // Arrow styles.
        arrowButtons = [
            (.tapered, ToolIcons.arrowTapered, "Tapered (Skitch-style)"), (.filled, ToolIcons.arrowFilled, "Filled"),
            (.open, ToolIcons.arrowOpen, "Open"), (.concave, ToolIcons.arrowConcave, "Concave"),
        ].map { style, glyph, tip in
            (style, ChromeButton(.seg, .glyph(glyph), toolTip: tip) { [weak self] in self?.setArrowStyle(style) })
        }
        arrowDoubleButton = ChromeButton(.seg, .glyph(ToolIcons.arrowDouble), toolTip: "Double-headed") { [weak self] in
            guard let self else { return }
            arrowDouble.toggle()
            applyToSelected { ($0 as? ArrowAnnotation)?.doubleHeaded = self.arrowDouble }
            syncOptionStates()
        }
        arrowPanel = hStack([DividerView()] + arrowButtons.map(\.1) + [DividerView(), arrowDoubleButton])

        // Text controls.
        fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        fontPopup.addItem(withTitle: TextLayout.systemFamily)
        fontPopup.menu?.addItem(.separator())
        fontPopup.addItems(withTitles: NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        fontPopup.target = self
        fontPopup.action = #selector(fontFamilyChanged(_:))
        fontPopup.controlSize = .small
        fontPopup.widthAnchor.constraint(equalToConstant: 150).isActive = true
        fontSizeCombo = NSComboBox()
        fontSizeCombo.addItems(withObjectValues: Self.fontSizes.map(String.init))
        fontSizeCombo.numberOfVisibleItems = 12
        fontSizeCombo.target = self
        fontSizeCombo.action = #selector(fontSizeCommitted(_:))
        fontSizeCombo.controlSize = .small
        fontSizeCombo.widthAnchor.constraint(equalToConstant: 64).isActive = true
        boldToggle = ChromeButton(.seg, .text("B", .boldSystemFont(ofSize: 13)), toolTip: "Bold") { [weak self] in
            guard let self else { return }
            bold.toggle()
            applyToSelected { ($0 as? TextAnnotation)?.bold = self.bold }
            restyleEditView()
            syncOptionStates()
        }
        italicToggle = ChromeButton(.seg, .text("I", NSFont(name: "Georgia-Italic", size: 13) ?? .systemFont(ofSize: 13)),
                                    toolTip: "Italic") { [weak self] in
            guard let self else { return }
            italic.toggle()
            applyToSelected { ($0 as? TextAnnotation)?.italic = self.italic }
            restyleEditView()
            syncOptionStates()
        }
        textPanel = hStack([DividerView(), fontPopup, spacer(6), fontSizeCombo, spacer(6), boldToggle, italicToggle])

        // Outline / filled.
        outlineToggle = ChromeButton(.seg, .custom(CGSize(width: 14, height: 10)) { r, fg in
            fg.setStroke()
            let p = NSBezierPath(rect: r.insetBy(dx: 0.85, dy: 0.85))
            p.lineWidth = 1.7
            p.stroke()
        }, toolTip: "Outline") { [weak self] in self?.setFilled(false) }
        filledToggle = ChromeButton(.seg, .custom(CGSize(width: 14, height: 10)) { r, fg in
            fg.setFill()
            r.fill()
        }, toolTip: "Filled") { [weak self] in self?.setFilled(true) }
        fillPanel = hStack([DividerView(), outlineToggle, filledToggle])

        // Obscure styles.
        obscureButtons = [(.pixelate, "Pixelate"), (.blur, "Blur"), (.block, "Block"), (.stripes, "Stripes")].map { style, name in
            let b = ChromeButton(.seg, .text(name, body)) { [weak self] in self?.setObscure(style) }
            b.padding = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
            return (style, b)
        }
        obscurePanel = hStack([DividerView()] + obscureButtons.map(\.1))

        // Stamps.
        stampButtons = [
            (.check, "✓", NSFont.boldSystemFont(ofSize: 13), "Check"), (.cross, "✕", .boldSystemFont(ofSize: 13), "Cross"),
            (.star, "★", body, "Star"), (.dot, "●", body, "Dot"), (.number, "1·2·3", body, "Auto-incrementing numbers"),
        ].map { kind, label, font, tip in
            let b = ChromeButton(.seg, .text(label, font), toolTip: tip) { [weak self] in self?.setStamp(kind) }
            if kind == .number { b.padding = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8) }
            return (kind, b)
        }
        stampPanel = hStack([DividerView()] + stampButtons.map(\.1))

        // Sticker.
        emojiButton = ChromeButton(.icon, .text(emoji, .systemFont(ofSize: 16)), toolTip: "Pick emoji")
        emojiButton.onClick = { [weak self] in
            guard let self else { return }
            Pickers.showEmojiPicker(from: emojiButton) { [weak self] e in
                self?.emoji = e
                self?.syncOptionStates()
            }
        }
        stickerPanel = hStack([DividerView(), emojiButton, spacer(8), makeLabel("click the image to place", size: 12, color: Theme.textDim)])
        spotlightPanel = hStack([DividerView(), makeLabel("drag to spotlight — everything else dims", size: 12, color: Theme.textDim)])

        normalBar = hStack([newCapture, DividerView(), toolIcon, spacer(6), toolNameLabel, DividerView(),
                            swatchPanel, swatchDivider, widthPanel, arrowPanel, textPanel, fillPanel,
                            obscurePanel, stampPanel, stickerPanel, spotlightPanel])
        normalBar.detachesHiddenViews = true
        normalBar.setClippingResistancePriority(.defaultLow, for: .horizontal)

        cropBar = buildCropBar()
        cropBar.isHidden = true

        let gear = ChromeButton(.icon, .glyph(ToolIcons.gear), toolTip: "Settings") { AppController.shared.showSettings() }
        settingsHost = hStack([DividerView(), gear])

        for v in [normalBar!, cropBar!, settingsHost!] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(v)
        }
        NSLayoutConstraint.activate([
            normalBar.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            normalBar.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            normalBar.trailingAnchor.constraint(lessThanOrEqualTo: settingsHost.leadingAnchor),
            settingsHost.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            settingsHost.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            cropBar.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            cropBar.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            cropBar.topAnchor.constraint(equalTo: bar.topAnchor),
            cropBar.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])
        return bar
    }

    private func buildCropBar() -> NSView {
        let body = NSFont.systemFont(ofSize: 13)
        let icon = ChromeButton(.icon, .glyph(ToolIcons.glyph(.crop)))
        icon.tint = Theme.accent
        icon.padding = NSEdgeInsets()
        cropWField = NSTextField(string: "")
        cropHField = NSTextField(string: "")
        for f in [cropWField!, cropHField!] {
            f.alignment = .center
            f.font = body
            f.delegate = self
            f.widthAnchor.constraint(equalToConstant: 58).isActive = true
        }
        aspectPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        aspectPopup.addItems(withTitles: Self.aspectPresets.map(\.0))
        aspectPopup.controlSize = .small
        aspectPopup.target = self
        aspectPopup.action = #selector(aspectChanged(_:))
        aspectPopup.widthAnchor.constraint(equalToConstant: 92).isActive = true
        lockToggle = ChromeButton(.seg, .glyph(ToolIcons.lock), toolTip: "Proportional lock") { [weak self] in
            guard let self else { return }
            lockToggle.isChecked.toggle()
            updateLock()
        }
        let left = hStack([icon, spacer(6), makeLabel("Crop", weight: .semibold, color: Theme.accent), DividerView(),
                           cropWField, spacer(6), makeLabel("×"), spacer(6), cropHField, spacer(10), aspectPopup,
                           spacer(6), lockToggle])
        let cancel = ChromeButton(.ghost, .text("Cancel", body)) { [weak self] in self?.exitCrop(apply: false) }
        let apply = ChromeButton(.primary, .text("Apply", body)) { [weak self] in self?.exitCrop(apply: true) }
        let right = hStack([cancel, spacer(8), apply])

        let host = NSView()
        for v in [left, right] {
            v.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(v)
        }
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            left.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            right.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            left.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -8),
        ])
        return host
    }

    static let aspectPresets: [(String, CGFloat)] = [("Free", 0), ("Original", -1), ("1:1", 1), ("4:3", 4.0 / 3), ("3:2", 1.5), ("16:9", 16.0 / 9)]

    func spacer(_ w: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: w).isActive = true
        return v
    }

    private static func drawRainbow(_ r: CGRect) {
        let colors: [NSColor] = [.systemRed, .orange, .yellow, NSColor(srgbRed: 0.2, green: 0.8, blue: 0.2, alpha: 1),
                                 NSColor(srgbRed: 0, green: 0.75, blue: 1, alpha: 1), NSColor(srgbRed: 0.58, green: 0.44, blue: 0.86, alpha: 1), .systemRed]
        let g = NSGradient(colors: colors, atLocations: [0, 0.18, 0.35, 0.52, 0.7, 0.86, 1], colorSpace: .sRGB)
        g?.draw(in: NSBezierPath(ovalIn: r), angle: -45)
        RGBAColor.pink.nsColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: r.midX - 3, y: r.midY - 3, width: 6, height: 6)).fill()
    }

    // MARK: - Rail

    func buildRail() -> NSView {
        let rail = BarView(divider: .right)
        let tools = NSStackView(views: ToolIcons.railOrder.map { kind in
            let b = ChromeButton(.rail, .glyph(ToolIcons.glyph(kind)), toolTip: kind.displayName) { [weak self] in
                self?.selectTool(kind)
            }
            railButtons[kind] = b
            return b
        })
        tools.orientation = .vertical
        tools.spacing = 2
        tools.alignment = .centerX

        let ruleView = RuleView()
        colorWell = ChromeButton(.icon, .custom(CGSize(width: 18, height: 18)) { [weak self] r, _ in
            guard let self else { return }
            color.nsColor.setFill()
            let p = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
            p.fill()
            Theme.divider.setStroke()
            p.lineWidth = 1
            p.stroke()
        }, toolTip: "Current color — click to change")
        colorWell.padding = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        colorWell.onClick = { [weak self] in
            guard let self else { return }
            // The well sits at the rail's foot: open sideways, not off the bottom of the window.
            Pickers.showColorPicker(from: colorWell, current: color, edge: .maxX) { [weak self] c in self?.setColor(c) }
        }

        for v in [tools, ruleView, colorWell!] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            rail.addSubview(v)
        }
        NSLayoutConstraint.activate([
            tools.topAnchor.constraint(equalTo: rail.topAnchor, constant: 6),
            tools.centerXAnchor.constraint(equalTo: rail.centerXAnchor, constant: -0.5),
            colorWell.bottomAnchor.constraint(equalTo: rail.bottomAnchor, constant: -10),
            colorWell.centerXAnchor.constraint(equalTo: rail.centerXAnchor, constant: -0.5),
            ruleView.bottomAnchor.constraint(equalTo: colorWell.topAnchor, constant: -8),
            ruleView.centerXAnchor.constraint(equalTo: rail.centerXAnchor, constant: -0.5),
            ruleView.widthAnchor.constraint(equalToConstant: 26),
            ruleView.heightAnchor.constraint(equalToConstant: 1),
            tools.bottomAnchor.constraint(lessThanOrEqualTo: ruleView.topAnchor, constant: -4),
        ])
        return rail
    }

    // MARK: - Bottom bar

    func buildBottomBar() -> NSView {
        let bar = BarView(divider: .top)
        let body = NSFont.systemFont(ofSize: 13)
        undoButton = ChromeButton(.icon, .glyph(ToolIcons.undo), toolTip: "Undo (⌘Z)") { [weak self] in self?.undoEdit(nil) }
        redoButton = ChromeButton(.icon, .glyph(ToolIcons.redo), toolTip: "Redo (⇧⌘Z)") { [weak self] in self?.redoEdit(nil) }
        let trash = ChromeButton(.icon, .glyph(ToolIcons.trash), toolTip: "Delete selection / clear all") { [weak self] in
            self?.trashClicked()
        }
        let zoomOut = ChromeButton(.icon, .text("−", .systemFont(ofSize: 15)), toolTip: "Zoom out") { [weak self] in
            self?.nudgeZoom(1 / 1.25)
        }
        zoomLabel = ChromeButton(.icon, .menuLabel(nil, "100%", body), toolTip: "Zoom")
        zoomLabel.onClick = { [weak self] in self?.showZoomMenu() }
        let zoomIn = ChromeButton(.icon, .text("+", .systemFont(ofSize: 15)), toolTip: "Zoom in") { [weak self] in
            self?.nudgeZoom(1.25)
        }
        sizeReadout = makeLabel("", size: 12, color: Theme.textDim)
        let left = hStack([undoButton, redoButton, trash, DividerView(), zoomOut, zoomLabel, zoomIn, DividerView(), sizeReadout])

        let drag = DragOutButton()
        drag.makeFile = { [weak self] in self?.writeTempPNG() }
        let copyButton = ChromeButton(.icon, .glyph(ToolIcons.copy), toolTip: "Copy image (⌘C)") { [weak self] in self?.copyImage() }
        saveButton = ChromeButton(.icon, .menuLabel(ToolIcons.save, "." + saveFormat, body), toolTip: "Save (⌘S)")
        saveButton.onClick = { [weak self] in self?.showSaveMenu() }
        shareButton = ChromeButton(.icon, .glyph(ToolIcons.share), toolTip: "Share")
        shareButton.onClick = { [weak self] in self?.shareImage(nil) }
        let right = hStack([drag, copyButton, saveButton, shareButton])

        for v in [left, right] {
            v.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(v)
        }
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            left.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            right.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            left.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -8),
        ])
        return bar
    }

    // MARK: - Tool switching

    func selectTool(_ kind: ToolKind) {
        commitTextEdit()
        if kind == .crop {
            setRailChecked(.crop)
            enterCrop()
            return
        }
        if canvas.cropMode { exitCrop(apply: false) }
        if kind == .image {
            insertImage(nil)
            return
        }

        tool = kind
        setRailChecked(kind)
        canvas.setTool(kind)
        toolIcon.content = .glyph(ToolIcons.glyph(kind))
        toolNameLabel.stringValue = kind.displayName

        if AppController.shared.settings.rememberLastTool {
            AppController.shared.settings.lastTool = kind.rawValue
            AppController.shared.saveSettings()
        }
        updateToolOptions()
    }

    func setRailChecked(_ kind: ToolKind) {
        for (k, b) in railButtons { b.isChecked = k == kind }
    }

    /// Shows only the option groups relevant to the active tool (contextual top bar).
    func updateToolOptions() {
        let hasColor: Bool = [.arrow, .text, .rectangle, .ellipse, .line, .highlight, .pen, .stamp].contains(tool)
        let hasWidth: Bool = [.arrow, .rectangle, .ellipse, .line, .highlight, .pen].contains(tool)
        swatchPanel.isHidden = !hasColor
        swatchDivider.isHidden = !(hasColor || hasWidth)
        widthPanel.isHidden = !hasWidth
        arrowPanel.isHidden = tool != .arrow
        textPanel.isHidden = tool != .text && !(canvas.selected is TextAnnotation) && editing == nil
        fillPanel.isHidden = !(tool == .rectangle || tool == .ellipse)
        obscurePanel.isHidden = tool != .obscure
        stampPanel.isHidden = tool != .stamp
        stickerPanel.isHidden = tool != .sticker
        spotlightPanel.isHidden = tool != .spotlight
        syncOptionStates()
    }

    func syncOptionStates() {
        for (s, b) in arrowButtons { b.isChecked = s == arrowStyle }
        arrowDoubleButton.isChecked = arrowDouble
        outlineToggle.isChecked = !shapeFilled
        filledToggle.isChecked = shapeFilled
        for (s, b) in obscureButtons { b.isChecked = s == obscureStyle }
        for (k, b) in stampButtons { b.isChecked = k == stampKind }
        emojiButton.content = .text(emoji, .systemFont(ofSize: 16))
        pxField.stringValue = String(Int(currentWidth.rounded()))
        for (v, b) in widthButtons { b.isChecked = abs(v - currentWidth) < 0.5 }
        boldToggle.isChecked = bold
        italicToggle.isChecked = italic
        syncTextControls()
        colorWell.needsDisplay = true
    }

    private func syncTextControls() {
        syncingSelection = true
        defer { syncingSelection = false }
        if fontPopup.itemTitles.contains(fontFamily) { fontPopup.selectItem(withTitle: fontFamily) } else { fontPopup.selectItem(at: 0) }
        fontSizeCombo.stringValue = fontSize == fontSize.rounded() ? String(Int(fontSize)) : String(Double(fontSize))
    }

    // MARK: - Style setters (also restyle the current selection, v1.4.1 behavior)

    func setColor(_ c: RGBAColor) {
        color = c
        AppController.shared.settings.defaultColor = c.hex
        AppController.shared.saveSettings()
        applyToSelected { $0.color = c }
        restyleEditView()
        syncOptionStates()
    }

    var currentWidth: CGFloat {
        get {
            let s = AppController.shared.settings
            switch tool {
            case .arrow: return CGFloat(s.arrowWidth)
            case .highlight: return CGFloat(s.highlightWidth)
            case .pen: return CGFloat(s.penWidth)
            default: return CGFloat(s.shapeWidth)
            }
        }
        set {
            let v = Double(newValue)
            switch tool {
            case .arrow: AppController.shared.settings.arrowWidth = v
            case .highlight: AppController.shared.settings.highlightWidth = v
            case .pen: AppController.shared.settings.penWidth = v
            default: AppController.shared.settings.shapeWidth = v
            }
            AppController.shared.saveSettings()
        }
    }

    func setWidth(_ value: CGFloat) {
        currentWidth = clamp(value, 1, 200)
        let w = currentWidth
        applyToSelected { $0.strokeWidth = w }
        syncOptionStates()
    }

    @objc func pxFieldCommitted(_ sender: NSTextField) {
        if let v = Double(sender.stringValue.trimmingCharacters(in: .whitespaces)) { setWidth(CGFloat(v)) } else { syncOptionStates() }
        window?.makeFirstResponder(canvas)
    }

    func setArrowStyle(_ style: ArrowStyle) {
        arrowStyle = style
        applyToSelected { ($0 as? ArrowAnnotation)?.style = style }
        syncOptionStates()
    }

    func setFilled(_ filled: Bool) {
        shapeFilled = filled
        applyToSelected { ($0 as? BoxAnnotation)?.filled = filled }
        syncOptionStates()
    }

    func setObscure(_ style: ObscureStyle) {
        obscureStyle = style
        AppController.shared.settings.obscureStyle = style.rawValue
        AppController.shared.saveSettings()
        applyToSelected { ($0 as? ObscureAnnotation)?.style = style }
        syncOptionStates()
    }

    func setStamp(_ kind: StampKind) {
        stampKind = kind
        syncOptionStates()
    }

    @objc func fontFamilyChanged(_ sender: NSPopUpButton) {
        guard !syncingSelection, let f = sender.titleOfSelectedItem else { return }
        fontFamily = f
        applyToSelected { ($0 as? TextAnnotation)?.fontFamily = f }
        restyleEditView()
    }

    @objc func fontSizeCommitted(_ sender: NSComboBox) {
        guard !syncingSelection else { return }
        let raw = sender.indexOfSelectedItem >= 0 && sender.stringValue.isEmpty
            ? Self.fontSizes[sender.indexOfSelectedItem].description : sender.stringValue
        let size = Double(raw.trimmingCharacters(in: .whitespaces)).map { CGFloat($0) } ?? fontSize
        fontSize = clamp(size, 6, 300)
        applyToSelected { ($0 as? TextAnnotation)?.fontSize = self.fontSize }
        restyleEditView()
    }

    func applyToSelected(_ change: (Annotation) -> Void) {
        guard let sel = canvas.selected else { return }
        doc.pushUndo()
        change(sel)
        doc.dirty = true
        doc.notifyChanged()
    }

    /// Selecting an annotation surfaces its style in the top bar (v1.4.1 parity for text).
    func selectionChanged() {
        if let t = canvas.selected as? TextAnnotation {
            textPanel.isHidden = false
            syncTextBar(t)
        } else if tool != .text && editing == nil {
            textPanel.isHidden = true
        }
    }

    /// Reflect a text annotation's style in the bar WITHOUT firing the change handlers.
    func syncTextBar(_ t: TextAnnotation) {
        fontFamily = t.fontFamily
        fontSize = t.fontSize
        bold = t.bold
        italic = t.italic
        boldToggle.isChecked = bold
        italicToggle.isChecked = italic
        syncTextControls()
    }
}

/// The 26×1 rule above the rail's color well.
@MainActor
final class RuleView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.divider.setFill()
        bounds.fill()
    }
}
