import ServiceManagement

/// Open at login via SMAppService.mainApp (windows/Sitch/Shell/StartupManager.cs used the
/// HKCU Run key). Only meaningful for the bundled app; a bare `swift run` binary can't register.
@MainActor
enum LoginItem {
    /// `.requiresApproval` (user switched it off in System Settings → Login Items) counts as off.
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Running from /Applications or ~/Applications — not from the mounted disk image, Downloads,
    /// or a Gatekeeper-translocated copy, where a login item would point at a path that vanishes.
    static var isInstalledApp: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return Bundle.main.bundleIdentifier != nil
            && (path.hasPrefix("/Applications/") || path.hasPrefix(userApps + "/"))
    }

    static func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }
}
