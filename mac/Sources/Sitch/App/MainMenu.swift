import AppKit

/// The menu bar shown while an editor is frontmost. Built in code (no nib). Editor commands
/// target the first responder, so they reach the key EditorWindowController; app commands
/// fall through to AppDelegate when no editor handles them.
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(item("About Sitch", #selector(AppDelegate.showAbout(_:))))
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(AppDelegate.showSettings(_:)), ","))
        app.addItem(.separator())
        app.addItem(item("Hide Sitch", #selector(NSApplication.hide(_:)), "h"))
        app.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item("Quit Sitch", #selector(NSApplication.terminate(_:)), "q"))
        main.addItem(submenu: app, title: "Sitch")

        let file = NSMenu(title: "File")
        file.addItem(item("New Capture", #selector(AppDelegate.newCaptureTab(_:)), "n"))
        file.addItem(item("Open Image…", #selector(AppDelegate.openImage(_:)), "o"))
        file.addItem(.separator())
        file.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        file.addItem(item("Save…", Sel.saveImage, "s"))
        file.addItem(item("Share…", Sel.shareImage))
        main.addItem(submenu: file, title: "File")

        // Text fields and the in-canvas text editor need the standard items to work at all;
        // undo/redo get their own selectors so a field's undo never touches the document.
        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", Sel.undoEdit, "z"))
        edit.addItem(item("Redo", Sel.redoEdit, "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Delete", Sel.deleteSelection))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        main.addItem(submenu: edit, title: "Edit")

        let image = NSMenu(title: "Image")
        image.addItem(item("Crop", Sel.startCrop, "k"))
        image.addItem(item("Insert Image…", Sel.insertImage, "i", [.command, .shift]))
        image.addItem(.separator())
        image.addItem(item("Rotate Left", Sel.rotateLeft, "l"))
        image.addItem(item("Rotate Right", Sel.rotateRight, "r"))
        image.addItem(item("Flip Horizontal", Sel.flipHorizontal))
        image.addItem(item("Flip Vertical", Sel.flipVertical))
        main.addItem(submenu: image, title: "Image")

        let view = NSMenu(title: "View")
        view.addItem(item("Actual Size", Sel.zoomActualSize, "0"))
        view.addItem(item("Zoom In", Sel.zoomIn, "="))
        view.addItem(item("Zoom Out", Sel.zoomOut, "-"))
        view.addItem(item("Zoom to Fit", Sel.zoomToFit, "9"))
        main.addItem(submenu: view, title: "View")

        let window = NSMenu(title: "Window")
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        main.addItem(submenu: window, title: "Window")
        NSApp.windowsMenu = window // AppKit adds the tab and window-list items itself

        return main
    }

    /// Editor actions, resolved through the responder chain (implemented by EditorWindowController).
    enum Sel {
        static let undoEdit = NSSelectorFromString("undoEdit:")
        static let redoEdit = NSSelectorFromString("redoEdit:")
        static let saveImage = NSSelectorFromString("saveImage:")
        static let shareImage = NSSelectorFromString("shareImage:")
        static let deleteSelection = NSSelectorFromString("deleteSelection:")
        static let startCrop = NSSelectorFromString("startCrop:")
        static let insertImage = NSSelectorFromString("insertImage:")
        static let rotateLeft = NSSelectorFromString("rotateLeft:")
        static let rotateRight = NSSelectorFromString("rotateRight:")
        static let flipHorizontal = NSSelectorFromString("flipHorizontal:")
        static let flipVertical = NSSelectorFromString("flipVertical:")
        static let zoomActualSize = NSSelectorFromString("zoomActualSize:")
        static let zoomIn = NSSelectorFromString("zoomIn:")
        static let zoomOut = NSSelectorFromString("zoomOut:")
        static let zoomToFit = NSSelectorFromString("zoomToFit:")
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "",
                             _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        return item
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
