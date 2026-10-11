import AppKit
import SitchCore

/// STUB — replaced by the Editor port. Public surface below is the contract other modules use.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    /// (Not `document`: NSWindowController already has one.)
    private(set) var doc: Document
    private(set) var docName: String

    init(image: CGImage, title: String, pointScale: CGFloat) {
        doc = Document(base: image, pointScale: pointScale)
        self.docName = title
        super.init(window: nil)
    }

    /// Used by --demo: a prepared document (annotations already placed).
    init(document: Document, title: String) {
        self.doc = document
        self.docName = title
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Size/position (on the display `sourceRect` came from, global top-left points), show, activate.
    func present(sourceRect: CGRect?) {}

    /// Opens `editor` as a native tab of this window (New Capture from inside an editor).
    func addTab(_ editor: EditorWindowController) {}

    /// Unsaved, non-pristine changes.
    var needsSavePrompt: Bool { doc.dirty && !doc.isPristine }

    /// Save prompt; false means the user cancelled the close.
    func confirmClose() -> Bool { true }

    /// Close after the caller already ran confirmClose (quit flow).
    func closeWithoutPrompt() {}

    /// --demo-crop: open straight into crop mode.
    func enterCropMode() {}
}
