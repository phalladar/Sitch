import AppKit

/// Entry point. Plain AppKit rather than a SwiftUI `App`: Sitch is menu-bar–resident like the
/// Windows tray app, and its windows are code-built, mirroring windows/Sitch.
@main
@MainActor
enum SitchMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var editors: [EditorWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement covers the bundled app; a bare `swift run` binary has no Info.plist.
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.build()
        menuBar = MenuBarController(app: self)
    }

    // Menu-bar resident: closing the last editor must not quit (Windows: OnExplicitShutdown).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func newEditor(_ sender: Any?) {
        let editor = EditorWindowController()
        editor.onClose = { [weak self, unowned editor] in self?.editorClosed(editor) }
        editors.append(editor)
        // Dock icon only while an editor is open — the Mac take on "Show in taskbar".
        NSApp.setActivationPolicy(.regular)
        editor.showWindow(nil)
        NSApp.activate()
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Capture. Annotate. Share.\nMIT License — github.com/phalladar/sitch"),
        ])
    }

    private func editorClosed(_ editor: EditorWindowController) {
        editors.removeAll { $0 === editor }
        if editors.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}
