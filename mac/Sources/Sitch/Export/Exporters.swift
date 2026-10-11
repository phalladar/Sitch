import AppKit
import SitchCore

/// STUB — replaced by the Export port. Public surface below is the contract other modules use.
enum Exporters {
    static let formats = ["png", "jpg", "pdf", "tiff"]

    /// Encodes by the URL's extension. `pointScale` sets DPI metadata / PDF page size.
    static func save(_ image: CGImage, to url: URL, pointScale: CGFloat) throws {}

    /// Quick-capture save: default folder (or ~/Pictures/Sitch), timestamped name, never overwrites.
    @MainActor static func quickSave(_ image: CGImage, pointScale: CGFloat) throws -> URL { URL(fileURLWithPath: "/") }
}

enum ClipboardHelper {
    /// PNG (keeps alpha) + TIFF on the general pasteboard. False if it couldn't be written.
    @MainActor @discardableResult static func copy(_ image: CGImage, pointScale: CGFloat) -> Bool { false }
}

enum TempFiles {
    /// Writes a PNG under $TMPDIR/Sitch for drag-out / share; caller tracks and removes it.
    static func writePNG(_ image: CGImage, name: String, pointScale: CGFloat) throws -> URL { URL(fileURLWithPath: "/") }
    static func remove(_ urls: [URL]) {}
}

enum ShareHelper {
    /// macOS share sheet for a file, anchored to `view`.
    @MainActor static func share(_ url: URL, from view: NSView) {}
}
