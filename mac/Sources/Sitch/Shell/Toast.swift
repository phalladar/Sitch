import AppKit

/// Small self-drawn toast, bottom-right of the screen with the pointer (windows/Sitch/Shell/
/// NotifyPopup.cs parity). Non-activating and click-through, so it never steals focus from
/// the app being captured; a new toast replaces the previous one.
@MainActor
enum Toast {
    private static var current: NSPanel?
    private static var generation = 0

    /// Small self-drawn toast, bottom-right of the active screen, fades after ~2 s.
    static func show(_ text: String, thumbnail: CGImage? = nil) {
        current?.orderOut(nil)
        generation += 1
        let gen = generation

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)

        if let thumbnail {
            let w = CGFloat(thumbnail.width), h = CGFloat(thumbnail.height)
            let fit = min(72 / w, 48 / h, 1)
            let size = NSSize(width: max(1, w * fit), height: max(1, h * fit))
            let iv = NSImageView(image: NSImage(cgImage: thumbnail, size: size))
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.wantsLayer = true
            iv.layer?.cornerRadius = 4
            iv.layer?.masksToBounds = true
            iv.widthAnchor.constraint(equalToConstant: size.width).isActive = true
            iv.heightAnchor.constraint(equalToConstant: size.height).isActive = true
            stack.addArrangedSubview(iv)
        }

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .white
        label.preferredMaxLayoutWidth = 260
        stack.addArrangedSubview(label)

        let bubble = NSView()
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = NSColor(srgbRed: 0x28 / 255.0, green: 0x28 / 255.0, blue: 0x2A / 255.0, alpha: 0xF2 / 255.0).cgColor
        bubble.layer?.cornerRadius = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bubble.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
        ])
        let size = stack.fittingSize

        let panel = overlayPanel(size: size)
        panel.contentView = bubble
        let screen = screenWithMouse()
        let vf = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 16, y: vf.minY + 16))
        panel.orderFrontRegardless()
        current = panel

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2200))
            guard gen == generation else { return }
            await NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                panel.animator().alphaValue = 0
            }
            panel.orderOut(nil)
            if gen == generation { current = nil }
        }
    }

    /// Borderless, click-through, on every Space — shared by Toast and Countdown.
    static func overlayPanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // NOT .statusBar: the capture freeze-frame drops Sitch's own windows above level 0
        // except .statusBar, so a toast/countdown there would land in the screenshot.
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    static func screenWithMouse() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
