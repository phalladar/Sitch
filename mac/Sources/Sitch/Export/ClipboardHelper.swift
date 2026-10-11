import AppKit
import SitchCore

/// Clipboard output (windows/Sitch/Export/ClipboardHelper.cs parity): PNG keeps transparency
/// for modern apps; TIFF is what older Cocoa apps paste. Full pixels, DPI-tagged for Retina.
enum ClipboardHelper {
    /// PNG (keeps alpha) + TIFF on the general pasteboard. False if it couldn't be written.
    @MainActor @discardableResult static func copy(_ image: CGImage, pointScale: CGFloat) -> Bool {
        guard let png = Exporters.data(image, type: .png, pointScale: pointScale) else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        var ok = pb.setData(png, forType: .png)
        if let tiff = Exporters.data(image, type: .tiff, pointScale: pointScale) {
            ok = pb.setData(tiff, forType: .tiff) && ok
        }
        return ok
    }
}
