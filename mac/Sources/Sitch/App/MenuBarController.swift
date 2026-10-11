import AppKit
import SitchCore

/// Menu-bar presence: the Mac counterpart of windows/Sitch/Shell/TrayController.cs. Same menu;
/// clicking opens it (macOS convention — the Windows tray icon captured on left-click).
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let captureItem = NSMenuItem(title: "Capture Region", action: #selector(AppDelegate.captureRegion(_:)), keyEquivalent: "")
    private let recaptureItem = NSMenuItem(title: "Recapture Last Region", action: #selector(AppDelegate.recaptureLast(_:)), keyEquivalent: "")
    private let fullScreen = NSMenuItem(title: "Capture Full Screen", action: nil, keyEquivalent: "")

    override init() {
        super.init()
        item.button?.image = Self.glyph
        item.button?.toolTip = "Sitch — Capture. Annotate. Share."

        let menu = NSMenu()
        menu.addItem(captureItem)
        menu.addItem(withTitle: "Capture Window", action: #selector(AppDelegate.captureWindow(_:)), keyEquivalent: "")
        fullScreen.submenu = NSMenu()
        fullScreen.submenu?.delegate = self
        menu.addItem(fullScreen)
        menu.addItem(recaptureItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quick Capture → Clipboard", action: #selector(AppDelegate.quickCaptureToClipboard(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Quick Capture → File", action: #selector(AppDelegate.quickCaptureToFile(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Image…", action: #selector(AppDelegate.openImage(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "About Sitch", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sitch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        for entry in menu.items where entry.action != nil && entry.action != #selector(NSApplication.terminate(_:)) {
            entry.target = NSApp.delegate
        }
        item.menu = menu
        refreshShortcuts()
    }

    /// Hotkeys are rebindable in Settings — show the current ones next to their items.
    func refreshShortcuts() {
        Self.show(AppController.shared.settings.captureHotkey, on: captureItem)
        Self.show(AppController.shared.settings.recaptureHotkey, on: recaptureItem)
    }

    // Displays come and go — rebuild the submenu each time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for (i, d) in CaptureController.displays().enumerated() {
            let entry = NSMenuItem(
                title: "Display \(i + 1) — \(d.name) (\(d.pixelWidth)×\(d.pixelHeight))\(d.isMain ? " — main" : "")",
                action: #selector(AppDelegate.captureFullScreen(_:)), keyEquivalent: "")
            entry.target = NSApp.delegate
            entry.representedObject = d.id
            menu.addItem(entry)
        }
        if menu.items.isEmpty { menu.addItem(withTitle: "No displays", action: nil, keyEquivalent: "") }
    }

    private static func show(_ hotkey: String, on item: NSMenuItem) {
        guard let chord = HotkeyChord.parse(hotkey), let key = keyEquivalent(for: chord.key) else {
            item.keyEquivalent = ""
            return
        }
        item.keyEquivalent = key
        var mods: NSEvent.ModifierFlags = []
        if chord.modifiers.contains(.command) { mods.insert(.command) }
        if chord.modifiers.contains(.option) { mods.insert(.option) }
        if chord.modifiers.contains(.control) { mods.insert(.control) }
        if chord.modifiers.contains(.shift) { mods.insert(.shift) }
        item.keyEquivalentModifierMask = mods
    }

    /// Display-only key equivalent (the global hotkey does the work; this just shows it).
    private static func keyEquivalent(for key: String) -> String? {
        if key.count == 1 { return key.lowercased() }
        if key.hasPrefix("F"), let n = Int(key.dropFirst()), (1...20).contains(n),
           let scalar = UnicodeScalar(NSF1FunctionKey + n - 1) {
            return String(Character(scalar))
        }
        return key == "Space" ? " " : nil
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
