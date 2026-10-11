import ServiceManagement

/// Open at login via SMAppService.mainApp (windows/Sitch/Shell/StartupManager.cs used the
/// HKCU Run key). Only meaningful for the bundled app; a bare `swift run` binary can't register.
@MainActor
enum LoginItem {
    /// `.requiresApproval` (user switched it off in System Settings → Login Items) counts as off.
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }
}
