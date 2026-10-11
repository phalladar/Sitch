import AppKit

/// Placeholder editor window: proves window lifecycle, native tabbing and the Dock-icon toggle.
/// The real editor (canvas, 14-tool rail, options) ports windows/Sitch/Editor in a later phase.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Untitled — Sitch"
        // Native window tabs stand in for the Windows editor's tab strip.
        window.tabbingIdentifier = "SitchEditor"
        window.tabbingMode = .preferred
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func windowWillClose(_ notification: Notification) { onClose?() }
}
