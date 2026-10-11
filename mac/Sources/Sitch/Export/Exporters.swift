import AppKit
import ImageIO
import SitchCore
import UniformTypeIdentifiers

enum ExportError: LocalizedError {
    case encodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodeFailed(let path): "Couldn't write \(path)."
        }
    }
}

/// File output (windows/Sitch/Export/Exporters.cs parity). Mac 1x is 72 dpi, so a Retina
/// capture is written at 72 × pointScale dpi and a PDF page is pixels / pointScale points —
/// both keep the size the capture had on screen.
enum Exporters {
    static let formats = ["png", "jpg", "pdf", "tiff"]

    /// Encodes by the URL's extension. `pointScale` sets DPI metadata / PDF page size.
    static func save(_ image: CGImage, to url: URL, pointScale: CGFloat) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            try savePDF(image, to: url, pointScale: pointScale)
            return
        }
        let type: UTType
        var source = image
        var props = dpiProperties(pointScale)
        switch ext {
        case "jpg", "jpeg":
            type = .jpeg
            // JPEG has no alpha: flatten explicitly instead of getting black transparency.
            source = Renderer.flattenToWhite(image)
            props[kCGImageDestinationLossyCompressionQuality] = 0.92
        case "tif", "tiff":
            type = .tiff
        default:
            type = .png
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ExportError.encodeFailed(url.path)
        }
        CGImageDestinationAddImage(dest, source, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.encodeFailed(url.path) }
    }

    /// In-memory encode (clipboard).
    static func data(_ image: CGImage, type: UTType, pointScale: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, dpiProperties(pointScale) as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    static func dpiProperties(_ pointScale: CGFloat) -> [CFString: Any] {
        let dpi = 72 * max(1, pointScale)
        return [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
    }

    /// Single page with the image at its on-screen size (pixels / pointScale points).
    private static func savePDF(_ image: CGImage, to url: URL, pointScale: CGFloat) throws {
        let scale = max(1, pointScale)
        var box = CGRect(x: 0, y: 0, width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: url.deletingPathExtension().lastPathComponent,
            kCGPDFContextCreator: "Sitch",
        ]
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else {
            throw ExportError.encodeFailed(url.path)
        }
        ctx.beginPDFPage(nil)
        ctx.interpolationQuality = .high
        ctx.draw(Renderer.flattenToWhite(image), in: box) // PDF space is y-up: draws upright
        ctx.endPDFPage()
        ctx.closePDF()
    }

    /// Quick-capture save: default folder (or ~/Pictures/Sitch), timestamped name, never overwrites.
    @MainActor static func quickSave(_ image: CGImage, pointScale: CGFloat) throws -> URL {
        let settings = AppController.shared.settings
        let fm = FileManager.default
        let configured = (settings.defaultSaveFolder as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        let folder: URL
        if !settings.defaultSaveFolder.isEmpty, fm.fileExists(atPath: configured, isDirectory: &isDir), isDir.boolValue {
            folder = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            folder = fm.urls(for: .picturesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Sitch", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let fmt = formats.contains(settings.defaultFormat) ? settings.defaultFormat : "png"
        let url = uniqueURL(in: folder, baseName: "Sitch \(timestamp(Date()))", ext: fmt)
        try save(image, to: url, pointScale: pointScale)
        return url
    }

    /// "yyyy-MM-dd at HH.mm.ss" — the same name pattern macOS and the Windows build use.
    static func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f.string(from: date)
    }

    /// Two captures in the same second must not overwrite each other: "name (2).png", …
    static func uniqueURL(in folder: URL, baseName: String, ext: String) -> URL {
        var url = folder.appendingPathComponent("\(baseName).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(baseName) (\(n)).\(ext)")
            n += 1
        }
        return url
    }
}
