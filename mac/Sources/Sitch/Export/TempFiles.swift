import CoreGraphics
import Foundation

/// Temp PNGs for drag-out and share; the editor tracks and removes them when it closes.
enum TempFiles {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Sitch", isDirectory: true)
    }

    /// Writes a PNG under $TMPDIR/Sitch for drag-out / share; caller tracks and removes it.
    static func writePNG(_ image: CGImage, name: String, pointScale: CGFloat) throws -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH.mm.ss"
        let url = directory.appendingPathComponent(safeFileName("\(name) \(f.string(from: Date())).png"))
        try Exporters.save(image, to: url, pointScale: pointScale)
        return url
    }

    static func remove(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    /// The name lands in Finder / the receiving app, so keep it readable — only strip separators.
    static func safeFileName(_ name: String) -> String {
        let s = String(name.map { "/:\\".contains($0) ? "_" : $0 }).trimmingCharacters(in: .whitespaces)
        return s.hasPrefix(".") ? "_" + s : s
    }
}
