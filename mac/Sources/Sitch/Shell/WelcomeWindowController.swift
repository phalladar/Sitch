import AppKit
import SitchCore

/// First-run welcome (windows/Sitch/Shell/WelcomeWindow.cs parity). Without it a fresh
/// install is nearly invisible: Sitch lives in the menu bar, which the notch can hide. On the
/// Mac it also walks through the Screen Recording grant every capture depends on.
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: WelcomeWindowController?

    static func show() {
        let controller = shared ?? WelcomeWindowController()
        shared = controller
        NSApp.activate()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private var targets: [ActionTarget] = []
    private var permissionStatus: NSTextField!
    private var permissionButton: NSButton!

    private var hotkey: String {
        let s = AppController.shared.settings.captureHotkey
        return HotkeyChord.parse(s)?.symbols ?? s
    }

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Welcome to Sitch"
        window.isReleasedWhenClosed = false
        window.level = .floating // like the Windows Topmost window: don't get lost behind others
        super.init(window: window)
        window.delegate = self
        build()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func windowDidBecomeKey(_ notification: Notification) { refreshPermission() }

    func windowWillClose(_ notification: Notification) { Self.shared = nil }

    private func build() {
        guard let window, let content = window.contentView else { return }

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.widthAnchor.constraint(equalToConstant: 44).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let title = NSTextField(labelWithString: "Sitch is ready")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let sub = NSTextField(labelWithString: "Capture. Annotate. Share.")
        sub.font = .systemFont(ofSize: 13)
        sub.textColor = .secondaryLabelColor
        let titles = NSStackView(views: [title, sub])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2
        let header = NSStackView(views: [icon, titles])
        header.spacing = 14

        permissionStatus = line("")
        permissionButton = NSButton(title: "Grant Screen Recording…", target: nil, action: nil)
        bind(permissionButton) { [weak self] in self?.grantPermission() }

        let settings = NSButton(title: "Settings", target: nil, action: nil)
        bind(settings) { [weak self] in
            AppController.shared.showSettings()
            self?.close()
        }
        let capture = NSButton(title: "Capture now  (\(hotkey))", target: nil, action: nil)
        capture.keyEquivalent = "\r"
        bind(capture) { [weak self] in
            self?.close()
            // Let the window vanish before the freeze-frame so it isn't in the shot.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                AppController.shared.captureRegion()
            }
        }
        // Leading spacer pushes the buttons right (dialog convention, like the Windows window).
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let buttons = NSStackView(views: [spacer, settings, capture])
        buttons.spacing = 8

        let stack = NSStackView(views: [
            header,
            line("Press  \(hotkey)  to capture — drag a region or click a window.", bold: true),
            line("Sitch lives in your menu bar: click the pink arrow for window and full-screen "
                 + "capture, quick capture to clipboard or file, and Settings."),
            line("Every capture is copied to your clipboard automatically, ready to paste."),
            permissionStatus,
            permissionButton,
            buttons,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(20, after: header)
        stack.setCustomSpacing(22, after: permissionButton)
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 440),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56),
        ])
        refreshPermission()
        sizeToContent()
    }

    private func sizeToContent() {
        guard let content = window?.contentView else { return }
        content.layoutSubtreeIfNeeded()
        window?.setContentSize(NSSize(width: 440, height: content.fittingSize.height))
    }

    private func refreshPermission() {
        if CGPreflightScreenCaptureAccess() {
            permissionStatus.stringValue = "✓ Screen Recording is allowed."
            permissionButton.isHidden = true
        } else {
            permissionStatus.stringValue = "Sitch needs the Screen Recording permission to capture. "
                + "Turn on Sitch in System Settings → Privacy & Security → Screen & System Audio Recording, "
                + "then quit and reopen Sitch — macOS only applies the change after a relaunch."
            permissionButton.isHidden = false
        }
        sizeToContent()
    }

    private func grantPermission() {
        // The first request adds Sitch to the list (and shows the system prompt); then open the pane.
        if !CGRequestScreenCaptureAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        refreshPermission()
    }

    private func line(_ text: String, bold: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: bold ? .semibold : .regular)
        label.preferredMaxLayoutWidth = 384
        return label
    }

    private func bind(_ control: NSControl, _ action: @escaping () -> Void) {
        let target = ActionTarget(action)
        control.target = target
        control.action = #selector(ActionTarget.fire(_:))
        targets.append(target)
    }
}
