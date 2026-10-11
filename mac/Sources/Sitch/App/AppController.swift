import AppKit
import SitchCore

/// App-wide coordinator — the Mac counterpart of windows/Sitch/App.xaml.cs: owns settings,
/// routes captures (after-capture actions), opens editors, hotkeys, menu bar, watcher.
/// CONTRACT FILE: other modules call only the members declared here.
@MainActor
final class AppController {
    static let shared = AppController()

    /// Mutate, then call `saveSettings()` (same pattern as Windows `App.Settings`).
    var settings = AppSettings()
    private(set) var firstRun = false

    func saveSettings() { SettingsStore.save(settings) }

    // MARK: - Capture entry points

    func captureRegion() {}
    func captureWindow() {}
    func captureFullScreen(displayID: CGDirectDisplayID) {}
    func recaptureLast() {}
    /// Interactive region capture that skips the editor entirely (v1.3 quick capture).
    func quickCapture(toClipboard: Bool) {}
    /// Region capture whose result opens as a new tab of `editor` (the editor's New Capture button).
    func captureRegion(into editor: EditorWindowController) {}

    // MARK: - Windows

    @discardableResult
    func openEditor(image: CGImage, title: String, pointScale: CGFloat, sourceRect: CGRect? = nil) -> EditorWindowController {
        let editor = EditorWindowController(image: image, title: title, pointScale: pointScale)
        editor.present(sourceRect: sourceRect)
        return editor
    }

    func openImage(at url: URL) {}
    func showOpenImagePanel() {}
    func showSettings() {}
    func showAbout() {}

    /// Re-read the hotkey settings and re-register both global hotkeys.
    func registerHotkeys() {}
    func updateScreenshotWatcher() {}
    func applyTheme() { Theme.apply(settings.theme) }

    /// Editors report in so the Dock icon / quit prompt know what is open.
    func editorDidOpen(_ editor: EditorWindowController) {}
    func editorDidClose(_ editor: EditorWindowController) {}
}
