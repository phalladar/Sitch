import AppKit

/// Menu-bar presence: the Mac counterpart of windows/Sitch/Shell/TrayController.cs. The capture
/// items join this menu as the capture port lands.
@MainActor
final class MenuBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(app: AppDelegate) {
        item.button?.image = Self.glyph
        item.button?.toolTip = "Sitch — Capture. Annotate. Share."

        let menu = NSMenu()
        menu.addItem(withTitle: "New Editor", action: #selector(AppDelegate.newEditor(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "About Sitch", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Sitch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for entry in menu.items where entry.action != #selector(NSApplication.terminate(_:)) {
            entry.target = app
        }
        item.menu = menu
    }

    /// The app icon's tapered arrow as a template image, so the menu bar tints it for light/dark.
    private static let glyph: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            // Outline from the icon's 256-px design (see scripts/make-icon.swift), fitted to 18 pt.
            let points: [(CGFloat, CGFloat)] =
                [(188, 73), (171, 161), (144, 134), (96, 213), (49, 165), (127, 117), (101, 90)]
            let scale: CGFloat = 16 / 140, cx: CGFloat = 118.5, cy: CGFloat = 143
            let path = NSBezierPath()
            for (i, (x, y)) in points.enumerated() {
                let p = NSPoint(x: 9 + (x - cx) * scale, y: 9 + (y - cy) * scale)
                if i == 0 { path.move(to: p) } else { path.line(to: p) }
            }
            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
