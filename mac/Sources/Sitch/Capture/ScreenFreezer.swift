import AppKit
import ScreenCaptureKit

/// One display in capture space: its Quartz frame (global points, top-left origin at the
/// primary display) and backing scale. The Mac counterpart of Windows' MonitorData.
struct DisplayGeometry {
    let id: CGDirectDisplayID
    let frame: CGRect
    let scale: CGFloat
    let name: String

    @MainActor static func all() -> [DisplayGeometry] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            return DisplayGeometry(id: id, frame: CGDisplayBounds(id), scale: screen.backingScaleFactor,
                                   name: screen.localizedName)
        }
    }

    /// Display under a point, else the one the rect overlaps most, else main.
    @MainActor static func containing(_ p: CGPoint, in displays: [DisplayGeometry]) -> DisplayGeometry? {
        displays.first { $0.frame.contains(p) } ?? displays.first { $0.id == CGMainDisplayID() } ?? displays.first
    }

    @MainActor static func mostOverlapping(_ r: CGRect, in displays: [DisplayGeometry]) -> DisplayGeometry? {
        displays.max { area($0.frame.intersection(r)) < area($1.frame.intersection(r)) }
            ?? displays.first
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}

/// AppKit global space (bottom-left origin) ↔ Quartz global space (top-left origin).
enum ScreenSpace {
    @MainActor static var primaryHeight: CGFloat { CGDisplayBounds(CGMainDisplayID()).height }

    @MainActor static func toQuartz(_ p: NSPoint) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }

    @MainActor static func toAppKit(_ r: CGRect) -> NSRect {
        NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}

/// ScreenCaptureKit stills (CGDisplayCreateImage / CGWindowListCreateImage are gone in
/// macOS 15). Every call fetches its own SCShareableContent and returns only CGImages, so no
/// non-Sendable SCK object ever crosses an actor boundary.
enum ScreenFreezer {
    enum Failure: Error { case displayNotFound, windowNotFound }

    /// Our own floating windows (toasts, countdown) must never land in a capture; editor
    /// windows (layer 0) and the menu-bar item stay in, like the Windows build's GDI grab.
    private static func ownFloatingWindows(_ content: SCShareableContent) -> [SCWindow] {
        let pid = ProcessInfo.processInfo.processIdentifier
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        return content.windows.filter {
            $0.owningApplication?.processID == pid && $0.windowLayer > 0 && $0.windowLayer != statusLayer
        }
    }

    private static func configuration(pixelWidth: Int, pixelHeight: Int) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = max(1, pixelWidth)
        config.height = max(1, pixelHeight)
        config.showsCursor = false
        config.captureResolution = .best
        return config
    }

    /// Full-resolution stills of the given displays, keyed by display ID.
    nonisolated static func captureDisplays(_ targets: [(id: CGDirectDisplayID, pixelSize: CGSize)]) async throws
        -> [CGDirectDisplayID: CGImage] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let excluded = ownFloatingWindows(content)
        var images: [CGDirectDisplayID: CGImage] = [:]
        for target in targets {
            guard let display = content.displays.first(where: { $0.displayID == target.id }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: excluded)
            let config = configuration(pixelWidth: Int(target.pixelSize.width.rounded()),
                                       pixelHeight: Int(target.pixelSize.height.rounded()))
            images[target.id] = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        }
        return images
    }

    /// A single window's own content (clean even when occluded), without its drop shadow.
    nonisolated static func captureWindow(_ windowID: CGWindowID) async throws -> (image: CGImage, scale: CGFloat) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else { throw Failure.windowNotFound }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = configuration(pixelWidth: Int((filter.contentRect.width * scale).rounded()),
                                   pixelHeight: Int((filter.contentRect.height * scale).rounded()))
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, scale)
    }

    /// Crops a display still to a rect in global points (clamped to the display).
    static func crop(_ image: CGImage, display: CGRect, to rect: CGRect) -> CGImage? {
        let r = rect.intersection(display)
        if r.isNull || r.width < 1 || r.height < 1 { return nil }
        // Effective scale from the image itself: robust to scaled display modes.
        let sx = CGFloat(image.width) / display.width, sy = CGFloat(image.height) / display.height
        let px = CGRect(x: ((r.minX - display.minX) * sx).rounded(), y: ((r.minY - display.minY) * sy).rounded(),
                        width: (r.width * sx).rounded(), height: (r.height * sy).rounded())
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        if px.isNull || px.width < 1 || px.height < 1 { return nil }
        return image.cropping(to: px)
    }

    static func isPermissionError(_ error: Error) -> Bool {
        (error as NSError).domain == SCStreamErrorDomain
            && (error as NSError).code == SCStreamError.userDeclined.rawValue
    }
}
