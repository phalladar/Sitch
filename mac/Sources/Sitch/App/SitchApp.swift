import AppKit
import ImageIO
import SitchCore
import UniformTypeIdentifiers

/// Entry point. Plain AppKit rather than a SwiftUI `App`: Sitch is menu-bar–resident like the
/// Windows tray app, and its windows are code-built, mirroring windows/Sitch.
@main
@MainActor
enum SitchMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())

        // Self-contained render+exit modes; never need (or should touch) a running instance.
        for arg in args {
            if let path = arg.value(of: "--shot-region=") {
                exit(writePNG(DemoDocument.regionShot(), to: path) ? 0 : 1)
            }
            if let path = arg.value(of: "--render-demo=") {
                let image = DemoDocument.document().flatMap { Renderer.renderToImage($0, spotlightDim: 0.55) }
                exit(writePNG(image, to: path) ? 0 : 1)
            }
        }

        // Another Sitch is running: hand it our args and bow out (Windows: named pipe).
        if SingleInstance.forwardToRunningInstance(args) { exit(0) }

        let app = NSApplication.shared
        let delegate = AppDelegate(arguments: args)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    private static func writePNG(_ image: CGImage?, to path: String) -> Bool {
        guard let image,
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                         UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}

private extension String {
    func value(of prefix: String) -> String? { hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let arguments: [String]
    private var launched = false
    private var pendingOpens: [URL] = []

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement covers the bundled app; a bare `swift run` binary has no Info.plist.
        NSApp.setActivationPolicy(.accessory)
        SingleInstance.listen { args in
            if args.isEmpty { AppController.shared.handleRelaunch() } else { AppController.shared.handle(arguments: args) }
        }
        AppController.shared.start(arguments: arguments + pendingOpens.map(\.path))
        launched = true
    }

    // Menu-bar resident: closing the last editor must not quit (Windows: OnExplicitShutdown).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppController.shared.shouldTerminate() ? .terminateNow : .terminateCancel
    }

    /// Finder "Open With", drops on the Dock icon, `open -a Sitch file.png`.
    func application(_ application: NSApplication, open urls: [URL]) {
        if launched { urls.forEach { AppController.shared.openImage(at: $0) } } else { pendingOpens += urls }
    }

    /// Opening the app again (Finder, Spotlight) while it runs.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppController.shared.handleRelaunch() }
        return true
    }

    // MARK: - Menu actions (also the responder-chain fallback when no editor is key)

    @objc func captureRegion(_ sender: Any?) { AppController.shared.captureRegion() }
    @objc func captureWindow(_ sender: Any?) { AppController.shared.captureWindow() }
    @objc func recaptureLast(_ sender: Any?) { AppController.shared.recaptureLast() }
    @objc func quickCaptureToClipboard(_ sender: Any?) { AppController.shared.quickCapture(toClipboard: true) }
    @objc func quickCaptureToFile(_ sender: Any?) { AppController.shared.quickCapture(toClipboard: false) }
    @objc func newCaptureTab(_ sender: Any?) { AppController.shared.captureRegion() }
    @objc func openImage(_ sender: Any?) { AppController.shared.showOpenImagePanel() }
    @objc func showSettings(_ sender: Any?) { AppController.shared.showSettings() }
    @objc func showAbout(_ sender: Any?) { AppController.shared.showAbout() }

    @objc func captureFullScreen(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CGDirectDisplayID else { return }
        AppController.shared.captureFullScreen(displayID: id)
    }
}
