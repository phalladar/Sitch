import AppKit
import SitchCore

/// STUBS — replaced by the Shell port. Public surface below is the contract other modules use.

enum Toast {
    /// Small self-drawn toast, bottom-right of the active screen, fades after ~2 s.
    @MainActor static func show(_ text: String, thumbnail: CGImage? = nil) {}
}

enum Countdown {
    /// Capture timer (3/5/10 s) shown center-screen, then runs `action` once it has vanished.
    @MainActor static func run(seconds: Int, then action: @escaping @MainActor () -> Void) { action() }
}

/// Global hotkeys via Carbon RegisterEventHotKey (no Accessibility permission needed).
@MainActor
final class HotkeyManager {
    var onPressed: ((Int) -> Void)?
    /// False if the combination is taken (or invalid).
    func register(id: Int, _ chord: HotkeyChord) -> Bool { false }
    func unregisterAll() {}
}

/// Open at login via SMAppService.mainApp.
@MainActor
enum LoginItem {
    static var isEnabled: Bool { false }
    static func setEnabled(_ on: Bool) throws {}
}

/// Opens the editor when macOS saves a screenshot (⇧⌘3/⇧⌘4/⇧⌘5) to its save location.
@MainActor
final class ScreenshotWatcher {
    init(onNewScreenshot: @escaping @MainActor (URL) -> Void) {}
    func stop() {}
}

@MainActor
final class SettingsWindowController: NSWindowController {
    static func show() {}
}

/// First-run welcome (incl. the Screen Recording permission step).
@MainActor
final class WelcomeWindowController: NSWindowController {
    static func show() {}
}
