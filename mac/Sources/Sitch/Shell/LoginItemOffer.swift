import AppKit

/// The one-time "Open Sitch at login?" offer. Made once, on the first launch from an
/// Applications folder: inside the first-run Welcome window when that shows, as an alert
/// otherwise (e.g. the welcome was used up by a first run straight off the disk image).
@MainActor
enum LoginItemOffer {
    static var isDue: Bool {
        LoginItem.isInstalledApp && !AppController.shared.settings.offeredLoginItem && !LoginItem.isEnabled
    }

    /// Opened from the mounted disk image (or a Gatekeeper-translocated copy) — not installed yet.
    static var isRunningFromDiskImage: Bool {
        let path = Bundle.main.bundleURL.path
        return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }

    static func ask() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Open Sitch when you log in?"
        alert.informativeText = "Sitch lives in your menu bar, so your capture shortcut works as soon as "
            + "your Mac starts. You can change this anytime in Settings."
        alert.addButton(withTitle: "Open at Login")
        alert.addButton(withTitle: "Not Now")
        record(accepted: alert.runModal() == .alertFirstButtonReturn)
    }

    static func record(accepted: Bool) {
        let app = AppController.shared
        app.settings.offeredLoginItem = true
        if accepted {
            do {
                try LoginItem.setEnabled(true)
                app.settings.openAtLogin = true
            } catch {
                Toast.show("Couldn't add Sitch to your login items.\n\(error.localizedDescription)")
            }
        }
        app.saveSettings()
    }
}
