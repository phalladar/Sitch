import AppKit

/// macOS share sheet (Windows: DataTransferManager). Share targets want files, so the
/// editor hands over a temp PNG.
enum ShareHelper {
    /// macOS share sheet for a file, anchored to `view`.
    @MainActor static func share(_ url: URL, from view: NSView) {
        NSSharingServicePicker(items: [url]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}
