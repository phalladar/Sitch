import AppKit
import ImageIO
import SitchCore
import UniformTypeIdentifiers

/// App-wide coordinator — the Mac counterpart of windows/Sitch/App.xaml.cs: owns settings,
/// routes captures (after-capture actions), opens editors, hotkeys, menu bar, watcher.
/// Other modules call only the members marked CONTRACT.
@MainActor
final class AppController {
    static let shared = AppController()

    /// CONTRACT. Mutate, then call `saveSettings()` (same pattern as Windows `App.Settings`).
    var settings = AppSettings()
    private(set) var firstRun = false

    private let capture = CaptureController()
    private let hotkeys = HotkeyManager()
    private var watcher: ScreenshotWatcher?
    private var menuBar: MenuBarController?
    private var editors: [EditorWindowController] = []

    private static let hkCapture = 1, hkRecapture = 2

    /// CONTRACT.
    func saveSettings() { SettingsStore.save(settings) }

    func start(arguments: [String]) {
        (settings, firstRun) = SettingsStore.load()
        applyTheme()
        NSApp.mainMenu = MainMenu.build()
        menuBar = MenuBarController()
        hotkeys.onPressed = { [weak self] id in
            switch id {
            case Self.hkCapture: self?.captureRegion()
            case Self.hkRecapture: self?.recaptureLast()
            default: break
            }
        }
        registerHotkeys()
        updateScreenshotWatcher()
        handle(arguments: arguments)

        // Fresh install launched with no task: without this, the only sign of life is a small
        // menu-bar icon (and macOS may hide it behind the notch) — i.e. nothing visible at all.
        if firstRun && arguments.isEmpty {
            saveSettings() // materialize settings so the welcome shows once
            WelcomeWindowController.show()
            NSApp.activate()
        }
    }

    // MARK: - Arguments (launch + forwarded from a second instance)

    func handle(arguments: [String]) {
        for arg in arguments {
            switch arg {
            case "--demo": openDemo()
            case "--demo-crop": openDemo(crop: true)
            case "--demo-light": Theme.apply("Light"); openDemo()
            case "--settings": showSettings()
            case "--capture": captureRegion()
            default:
                if FileManager.default.fileExists(atPath: arg) { openImage(at: URL(fileURLWithPath: arg)) }
            }
        }
    }

    /// A second launch with nothing to do: say so instead of doing nothing (the classic
    /// "I double-clicked it and nothing happened").
    func handleRelaunch() {
        if let editor = editors.last {
            editor.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else {
            let key = HotkeyChord.parse(settings.captureHotkey)?.symbols ?? settings.captureHotkey
            Toast.show("Sitch is already running in the menu bar.\nPress \(key) to capture.")
        }
    }

    private func openDemo(crop: Bool = false) {
        guard let doc = DemoDocument.document() else { return }
        let editor = EditorWindowController(document: doc, title: "Q3 Dashboard")
        editor.present(sourceRect: nil)
        if crop { editor.enterCropMode() }
    }

    // MARK: - Capture entry points (CONTRACT)

    func captureRegion() { startCapture(.region) }
    func captureWindow() { startCapture(.window) }

    func captureRegion(into editor: EditorWindowController) {
        runWithTimer { [weak self, weak editor] in
            self?.capture.startInteractive(.region) { [weak self, weak editor] result in
                self?.route(result, into: editor)
            }
        }
    }

    func captureFullScreen(displayID: CGDirectDisplayID) {
        runWithTimer { [weak self] in
            Task { @MainActor in
                guard let self, let result = await self.capture.captureDisplay(displayID) else { return }
                self.route(result)
            }
        }
    }

    func recaptureLast() {
        guard let r = settings.lastRegion, r.width > 0, r.height > 0 else { captureRegion(); return }
        runWithTimer { [weak self] in
            Task { @MainActor in
                guard let self, let result = await self.capture.captureRect(r.cgRect) else { return }
                self.route(result)
            }
        }
    }

    /// Interactive region capture that skips the editor entirely (v1.3 quick capture).
    func quickCapture(toClipboard: Bool) {
        capture.startInteractive(.region) { [weak self] result in
            guard let self else { return }
            rememberRegion(result)
            defer { returnFocusIfIdle() }
            if toClipboard, ClipboardHelper.copy(result.image, pointScale: result.pointScale) {
                Toast.show("Copied to clipboard.", thumbnail: result.image)
                return
            }
            // Clipboard held by another app (or "to file" was asked for) — don't lose the frame.
            do {
                let url = try Exporters.quickSave(result.image, pointScale: result.pointScale)
                Toast.show(toClipboard ? "Clipboard busy — saved \(url.lastPathComponent) instead."
                                       : "Saved \(url.lastPathComponent)", thumbnail: result.image)
            } catch {
                Toast.show("Couldn't save the capture.\n\(error.localizedDescription)")
            }
        }
    }

    private func startCapture(_ mode: CaptureMode) {
        runWithTimer { [weak self] in
            self?.capture.startInteractive(mode) { [weak self] result in self?.route(result) }
        }
    }

    private func runWithTimer(_ action: @escaping @MainActor () -> Void) {
        let secs = settings.timerSeconds
        if [3, 5, 10].contains(secs) { Countdown.run(seconds: secs, then: action) } else { action() }
    }

    /// Applies the configured after-capture actions (show / copy / save, any combo). With
    /// `into` (the editor's own New Capture button) the frame always opens as a new tab there.
    private func route(_ result: CaptureResult, into: EditorWindowController? = nil) {
        rememberRegion(result)
        var handled = false
        if settings.afterCopy {
            if ClipboardHelper.copy(result.image, pointScale: result.pointScale) {
                Toast.show("Copied to clipboard.", thumbnail: result.image)
                handled = true // a failed copy must NOT count — the editor fallback keeps the frame
            } else {
                Toast.show("Clipboard is busy — opening the editor instead.")
            }
        }
        if settings.afterSave {
            do {
                let url = try Exporters.quickSave(result.image, pointScale: result.pointScale)
                Toast.show("Saved \(url.lastPathComponent)", thumbnail: result.image)
                handled = true
            } catch {
                Toast.show("Couldn't save the capture.\n\(error.localizedDescription)")
            }
        }
        if let into {
            into.addTab(EditorWindowController(image: result.image, title: "Untitled", pointScale: result.pointScale))
        } else if settings.afterShowEditor || !handled {
            openEditor(image: result.image, title: "Untitled", pointScale: result.pointScale, sourceRect: result.sourceRect)
        } else {
            returnFocusIfIdle()
        }
    }

    /// The overlay activated Sitch; with no editor to show, hand focus back to the app the
    /// user was in rather than leaving an invisible app frontmost.
    private func returnFocusIfIdle() {
        if editors.isEmpty { NSApp.deactivate() }
    }

    private func rememberRegion(_ result: CaptureResult) {
        guard result.kind == .region, let r = result.region else { return }
        settings.lastRegion = PixelRect(x: Int(r.minX.rounded()), y: Int(r.minY.rounded()),
                                        width: Int(r.width.rounded()), height: Int(r.height.rounded()))
        saveSettings()
    }

    // MARK: - Windows (CONTRACT)

    @discardableResult
    func openEditor(image: CGImage, title: String, pointScale: CGFloat, sourceRect: CGRect? = nil) -> EditorWindowController {
        let editor = EditorWindowController(image: image, title: title, pointScale: pointScale)
        editor.present(sourceRect: sourceRect)
        return editor
    }

    func openImage(at url: URL) {
        guard let (image, scale) = Self.loadImage(url) else {
            let alert = NSAlert()
            alert.messageText = "Couldn't open \(url.lastPathComponent)"
            alert.informativeText = "The file isn't an image Sitch can read."
            alert.runModal()
            return
        }
        openEditor(image: image, title: url.deletingPathExtension().lastPathComponent, pointScale: scale)
    }

    /// Decodes with EXIF orientation applied; a 144-dpi PNG (a macOS Retina screenshot)
    /// opens with point scale 2 so it keeps its on-screen size on export.
    static func loadImage(_ url: URL) -> (CGImage, CGFloat)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let dpi = (props[kCGImagePropertyDPIWidth] as? Double) ?? 72
        return (image, max(1, (dpi / 72).rounded()))
    }

    func showOpenImagePanel() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { openImage(at: url) }
    }

    func showSettings() {
        NSApp.activate()
        SettingsWindowController.show()
    }

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "Skitch-style screenshot annotation.\nCapture. Annotate. Share.\n\nMIT License — github.com/phalladar/sitch",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }

    /// Re-read the hotkey settings and re-register both global hotkeys.
    func registerHotkeys() {
        hotkeys.unregisterAll()
        if let cap = HotkeyChord.parse(settings.captureHotkey), !hotkeys.register(id: Self.hkCapture, cap) {
            Toast.show("Capture shortcut \(cap.symbols) is in use by another app.")
        }
        if let re = HotkeyChord.parse(settings.recaptureHotkey), !hotkeys.register(id: Self.hkRecapture, re) {
            Toast.show("Recapture shortcut \(re.symbols) is in use by another app.")
        }
        menuBar?.refreshShortcuts()
    }

    /// Settings' shortcut recorder needs the chords unregistered while it listens.
    func suspendHotkeys(_ suspended: Bool) {
        if suspended { hotkeys.unregisterAll() } else { registerHotkeys() }
    }

    func updateScreenshotWatcher() {
        watcher?.stop()
        watcher = settings.watchSystemScreenshots
            ? ScreenshotWatcher { [weak self] url in self?.openImage(at: url) }
            : nil
    }

    func applyTheme() { Theme.apply(settings.theme) }

    /// Editors report in so the Dock icon and the quit prompt know what is open.
    func editorDidOpen(_ editor: EditorWindowController) {
        if !editors.contains(where: { $0 === editor }) { editors.append(editor) }
        // Dock icon only while an editor is open — the Mac take on "show in taskbar".
        if settings.showInDock { NSApp.setActivationPolicy(.regular) }
    }

    func editorDidClose(_ editor: EditorWindowController) {
        editors.removeAll { $0 === editor }
        if editors.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    /// Quit: every dirty editor gets a chance to veto, then all close without re-prompting.
    func shouldTerminate() -> Bool {
        for editor in editors where editor.needsSavePrompt {
            editor.window?.makeKeyAndOrderFront(nil)
            if !editor.confirmClose() { return false }
        }
        for editor in editors { editor.closeWithoutPrompt() }
        return true
    }
}
