import AppKit

/// macOS Screen Recording privacy grant (TCC); required before any capture. The grant is tied
/// to the code signature, so ad-hoc rebuilds lose it (sign dev builds with the Developer ID).
@MainActor
enum ScreenRecordingPermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Triggers the system prompt (first time only); returns the current grant.
    @discardableResult static func request() -> Bool { CGRequestScreenCaptureAccess() }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private static let askedKey = "ScreenRecordingPermissionRequested"

    /// True when capture may proceed. Otherwise asks once via the system prompt (it has its own
    /// "Open System Settings" button) and on later attempts explains how to grant it.
    static func ensureGranted() -> Bool {
        if isGranted { return true }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: askedKey) {
            defaults.set(true, forKey: askedKey)
            if request() { return true }
            return false
        }
        showDeniedAlert()
        return false
    }

    /// Also used when ScreenCaptureKit refuses mid-session (grant revoked, user declined).
    static func showDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Sitch needs Screen Recording permission"
        alert.informativeText = "Turn on Sitch in System Settings → Privacy & Security → "
            + "Screen & System Audio Recording, then relaunch Sitch."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { openSystemSettings() }
    }
}
