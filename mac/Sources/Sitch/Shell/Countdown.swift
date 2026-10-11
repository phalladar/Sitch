import AppKit

/// Capture-timer countdown shown center-screen (windows/Sitch/Shell/CountdownPopup.cs parity).
@MainActor
enum Countdown {
    /// Capture timer (3/5/10 s) shown center-screen, then runs `action` once it has vanished.
    static func run(seconds: Int, then action: @escaping @MainActor () -> Void) {
        guard seconds > 0 else { action(); return }

        let size = NSSize(width: 140, height: 140)
        let label = NSTextField(labelWithString: String(seconds))
        label.font = .systemFont(ofSize: 64, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let box = NSView(frame: NSRect(origin: .zero, size: size))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(srgbRed: 0x1E / 255.0, green: 0x1E / 255.0, blue: 0x20 / 255.0, alpha: 0xD8 / 255.0).cgColor
        box.layer?.cornerRadius = 24
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])

        let panel = Toast.overlayPanel(size: size)
        panel.hasShadow = false
        panel.contentView = box
        let frame = Toast.screenWithMouse().frame
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
        panel.orderFrontRegardless()

        Task { @MainActor in
            var remaining = seconds
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                remaining -= 1
                if remaining > 0 { label.stringValue = String(remaining) }
            }
            panel.orderOut(nil)
            // Give the window server a beat to remove it before the freeze-frame.
            try? await Task.sleep(for: .milliseconds(120))
            action()
        }
    }
}
