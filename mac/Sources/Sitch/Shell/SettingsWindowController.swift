import AppKit
import SitchCore

/// Settings: General / Capture / Editor pages (windows/Sitch/Editor/SettingsWindow.xaml parity).
/// Native AppKit controls; every change persists immediately, like the Windows window.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?

    static func show() {
        let controller = shared ?? SettingsWindowController()
        shared = controller
        NSApp.activate()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private var targets: [ActionTarget] = []
    private var pages: [NSView] = []
    private var loginBox: NSButton!
    private var recorders: [HotkeyRecorder] = []

    private var app: AppController { AppController.shared }

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Sitch Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        build()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func windowDidBecomeKey(_ notification: Notification) {
        // System Settings → Login Items can flip this behind our back.
        loginBox?.state = LoginItem.isEnabled ? .on : .off
    }

    func windowWillClose(_ notification: Notification) {
        recorders.forEach { $0.stopRecording(commit: false) }
    }

    // MARK: - Layout

    private func build() {
        guard let content = window?.contentView else { return }

        let tabs = NSSegmentedControl(labels: ["General", "Capture", "Editor"], trackingMode: .selectOne,
                                      target: nil, action: nil)
        tabs.selectedSegment = 0
        bind(tabs) { [weak self] in self?.showPage(tabs.selectedSegment) }

        pages = [generalPage(), capturePage(), editorPage()]

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let footer = NSTextField(labelWithString: "Sitch \(version)")
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor

        let pageHost = NSView()
        for page in pages {
            page.translatesAutoresizingMaskIntoConstraints = false
            pageHost.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
                page.topAnchor.constraint(equalTo: pageHost.topAnchor),
            ])
        }

        for v in [tabs, pageHost, footer] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            tabs.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            pageHost.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 10),
            pageHost.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            pageHost.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            pageHost.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
        showPage(0)
    }

    private func showPage(_ index: Int) {
        for (i, page) in pages.enumerated() { page.isHidden = i != index }
        recorders.forEach { $0.stopRecording(commit: false) }
    }

    private func page(_ rows: [NSView]) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        return stack
    }

    private func section(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        // Extra space above each header (the stack spacing alone is too tight between groups).
        let wrap = NSStackView(views: [label])
        wrap.edgeInsets = NSEdgeInsets(top: 14, left: 0, bottom: 2, right: 0)
        return wrap
    }

    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 470
        return label
    }

    private func row(_ title: String, _ control: NSView, labelWidth: CGFloat = 150) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        let stack = NSStackView(views: [label, control])
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func checkbox(_ title: String, _ on: Bool, _ changed: @escaping (Bool) -> Void) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        box.state = on ? .on : .off
        bind(box) { changed(box.state == .on) }
        return box
    }

    private func numberField(_ value: Double, _ range: ClosedRange<Double>, _ commit: @escaping (Double) -> Void) -> NSTextField {
        let field = NSTextField(string: Self.format(value))
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 70).isActive = true
        // Fires on Return and on losing focus, so a typed value is never silently dropped.
        field.cell?.sendsActionOnEndEditing = true
        bind(field) {
            if let v = Double(field.stringValue.trimmingCharacters(in: .whitespaces)) {
                let clamped = clamp(v, range.lowerBound, range.upperBound)
                commit(clamped)
                field.stringValue = Self.format(clamped)
            }
        }
        return field
    }

    private static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    // MARK: - Pages

    private func generalPage() -> NSView {
        let s = app.settings
        let themes = ["System", "Light", "Dark"]
        var radios: [NSButton] = []
        for t in themes {
            let r = NSButton(radioButtonWithTitle: t, target: nil, action: nil)
            r.state = s.theme == t || (t == "System" && !themes.contains(s.theme)) ? .on : .off
            bind(r) { [weak self] in
                radios.forEach { $0.state = $0 === r ? .on : .off }
                self?.app.settings.theme = t
                self?.app.saveSettings()
                self?.app.applyTheme()
            }
            radios.append(r)
        }
        let themeRow = NSStackView(views: radios)
        themeRow.spacing = 18

        let dock = checkbox("Show a Dock icon while an editor is open", s.showInDock) { [weak self] on in
            self?.app.settings.showInDock = on
            self?.app.saveSettings()
        }
        loginBox = checkbox("Open at login", LoginItem.isEnabled) { [weak self] on in
            self?.setLogin(on)
        }

        return page([
            section("Appearance"), themeRow,
            section("Behavior"), dock, loginBox,
            note("Sitch lives in your menu bar — click the pink arrow to capture, or use the menu for everything else."),
        ])
    }

    private func setLogin(_ on: Bool) {
        do {
            try LoginItem.setEnabled(on)
            app.settings.openAtLogin = on
            app.saveSettings()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't update the login item."
            alert.informativeText = error.localizedDescription
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
        }
        loginBox.state = LoginItem.isEnabled ? .on : .off
    }

    private func capturePage() -> NSView {
        let s = app.settings

        let capture = HotkeyRecorder(chord: s.captureHotkey) { [weak self] chord in
            self?.app.settings.captureHotkey = chord
            self?.app.saveSettings()
            self?.app.registerHotkeys()
        }
        let recapture = HotkeyRecorder(chord: s.recaptureHotkey) { [weak self] chord in
            self?.app.settings.recaptureHotkey = chord
            self?.app.saveSettings()
            self?.app.registerHotkeys()
        }
        recorders = [capture, recapture]

        let folder = NSTextField(string: s.defaultSaveFolder)
        folder.placeholderString = "~/Pictures/Sitch"
        folder.cell?.sendsActionOnEndEditing = true
        folder.widthAnchor.constraint(equalToConstant: 360).isActive = true
        bind(folder) { [weak self] in
            self?.app.settings.defaultSaveFolder = folder.stringValue.trimmingCharacters(in: .whitespaces)
            self?.app.saveSettings()
        }
        let browse = NSButton(title: "Browse…", target: nil, action: nil)
        bind(browse) { [weak self] in self?.browseFolder(folder) }
        let folderRow = NSStackView(views: [folder, browse])
        folderRow.spacing = 8

        let format = NSPopUpButton(frame: .zero, pullsDown: false)
        format.addItems(withTitles: Exporters.formats)
        format.selectItem(withTitle: Exporters.formats.contains(s.defaultFormat) ? s.defaultFormat : "png")
        bind(format) { [weak self] in
            guard let f = format.titleOfSelectedItem else { return }
            self?.app.settings.defaultFormat = f
            self?.app.saveSettings()
        }

        let show = checkbox("Show the editor", s.afterShowEditor) { [weak self] on in
            self?.app.settings.afterShowEditor = on; self?.app.saveSettings()
        }
        let copy = checkbox("Copy to clipboard", s.afterCopy) { [weak self] on in
            self?.app.settings.afterCopy = on; self?.app.saveSettings()
        }
        let save = checkbox("Save to file", s.afterSave) { [weak self] on in
            self?.app.settings.afterSave = on; self?.app.saveSettings()
        }

        let timerValues = [0, 3, 5, 10]
        let timer = NSPopUpButton(frame: .zero, pullsDown: false)
        timer.addItems(withTitles: ["Off", "3 s", "5 s", "10 s"])
        timer.selectItem(at: timerValues.firstIndex(of: s.timerSeconds) ?? 0)
        bind(timer) { [weak self] in
            self?.app.settings.timerSeconds = timerValues[max(0, timer.indexOfSelectedItem)]
            self?.app.saveSettings()
        }

        let watch = checkbox("Open the editor after a system screenshot (⇧⌘3 / ⇧⌘4)", s.watchSystemScreenshots) { [weak self] on in
            self?.app.settings.watchSystemScreenshots = on
            self?.app.saveSettings()
            self?.app.updateScreenshotWatcher()
        }

        return page([
            section("Shortcuts"),
            row("Capture", capture.button),
            row("Recapture last region", recapture.button),
            note("Click a shortcut, then press the new combination (e.g. ⌥⌘4). Esc reverts."),
            section("Saving"), folderRow,
            row("Default format", format, labelWidth: 110),
            section("After capturing"), show, copy, save,
            section("Timer & watcher"),
            row("Capture timer", timer, labelWidth: 110),
            watch,
        ])
    }

    private func browseFolder(_ field: NSTextField) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        let current = (field.stringValue as NSString).expandingTildeInPath
        if !current.isEmpty { panel.directoryURL = URL(fileURLWithPath: current, isDirectory: true) }
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                field.stringValue = url.path
                self?.app.settings.defaultSaveFolder = url.path
                self?.app.saveSettings()
            }
        }
    }

    private func editorPage() -> NSView {
        let s = app.settings
        let remember = checkbox("Remember the last used tool", s.rememberLastTool) { [weak self] on in
            self?.app.settings.rememberLastTool = on; self?.app.saveSettings()
        }
        let arrow = numberField(s.arrowWidth, 1...200) { [weak self] v in
            self?.app.settings.arrowWidth = v; self?.app.saveSettings()
        }
        let text = numberField(s.textSize, 6...300) { [weak self] v in
            self?.app.settings.textSize = v; self?.app.saveSettings()
        }

        let dimLabel = NSTextField(labelWithString: "\(Int((s.spotlightDim * 100).rounded()))%")
        let dim = NSSlider(value: clamp(s.spotlightDim * 100, 20, 90), minValue: 20, maxValue: 90, target: nil, action: nil)
        dim.numberOfTickMarks = 15
        dim.allowsTickMarkValuesOnly = true
        dim.widthAnchor.constraint(equalToConstant: 220).isActive = true
        bind(dim) { [weak self] in
            dimLabel.stringValue = "\(Int(dim.doubleValue.rounded()))%"
            self?.app.settings.spotlightDim = dim.doubleValue / 100
            self?.app.saveSettings()
        }
        let dimRow = NSStackView(views: [dim, dimLabel])
        dimRow.spacing = 10

        return page([
            section("Tools"), remember,
            row("Arrow width (px)", arrow),
            row("Text size (pt)", text),
            section("Spotlight"), dimRow,
            note("How much everything outside a spotlight is dimmed."),
        ])
    }

    private func bind(_ control: NSControl, _ action: @escaping () -> Void) {
        let target = ActionTarget(action)
        control.target = target
        control.action = #selector(ActionTarget.fire(_:))
        targets.append(target)
    }
}

/// Closure-backed target/action (AppKit controls hold their target weakly, so keep these alive).
@MainActor
final class ActionTarget: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire(_ sender: Any?) { action() }
}

/// Click, press a combination, done (Windows: WireHotkeyRecorder). Esc / Delete reverts.
/// Bare keys would fire constantly while typing elsewhere, so a modifier is required unless
/// it's an F-key.
@MainActor
final class HotkeyRecorder: NSObject {
    let button: NSButton
    private var chord: String
    private let commit: (String) -> Void
    private var monitor: Any?

    init(chord: String, commit: @escaping (String) -> Void) {
        self.chord = chord
        self.commit = commit
        button = NSButton(title: "", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        super.init()
        button.target = self
        button.action = #selector(clicked(_:))
        button.toolTip = "Click, then press the new key combination"
        refresh()
    }

    private func refresh() {
        button.title = HotkeyChord.parse(chord)?.symbols ?? (chord.isEmpty ? "None" : chord)
    }

    @objc private func clicked(_ sender: Any?) {
        if monitor != nil { stopRecording(commit: false); return }
        button.title = "Press keys…"
        // Registered Carbon hotkeys swallow their chord before any monitor sees it, so pressing
        // the current shortcut would fire a capture instead of being recorded.
        AppController.shared.suspendHotkeys(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            let swallow = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return swallow ? nil : event
        }
    }

    /// True = the event was consumed by the recorder.
    private func handle(_ event: NSEvent) -> Bool {
        if event.type == .leftMouseDown {
            // Clicking anywhere else abandons the recording; clicking the button toggles it.
            let local = button.superview?.convert(event.locationInWindow, from: nil) ?? .zero
            if event.window !== button.window || !button.frame.contains(local) {
                stopRecording(commit: false)
            }
            return false
        }
        let code = Int(event.keyCode)
        if code == 0x35 || code == 0x33 { // Escape, Delete
            stopRecording(commit: false)
            return true
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: HotkeyChord.Modifiers = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.shift) { mods.insert(.shift) }
        guard let key = HotkeyChord.keyName(forKeyCode: code) else { NSSound.beep(); return true }
        let candidate = HotkeyChord(modifiers: mods, key: key)
        guard !mods.isEmpty || candidate.isStandaloneKey else { NSSound.beep(); return true }
        chord = candidate.description
        stopRecording(commit: true)
        return true
    }

    func stopRecording(commit doCommit: Bool) {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        AppController.shared.suspendHotkeys(false)
        refresh()
        if doCommit { commit(chord) }
    }
}
