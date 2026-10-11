import AppKit

/// Opens the editor when macOS saves a screenshot (⇧⌘3/⇧⌘4/⇧⌘5) to its save location
/// (windows/Sitch/Shell/ScreenshotWatcher.cs parity, which watched Pictures\Screenshots).
@MainActor
final class ScreenshotWatcher {
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff"]

    private let folder: URL
    private let onNew: @MainActor (URL) -> Void
    private let startedAt = Date()
    private var seen: Set<String> = []
    private var source: DispatchSourceFileSystemObject?

    init(onNewScreenshot: @escaping @MainActor (URL) -> Void) {
        onNew = onNewScreenshot
        folder = Self.screenshotFolder()
        seen = Set(imageNames())  // pre-existing files are never "new"

        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    /// The screencapture `location` default, else ~/Desktop (the macOS default).
    static func screenshotFolder() -> URL {
        let fm = FileManager.default
        if let raw = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !raw.isEmpty {
            let path = (raw as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return fm.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    private func imageNames() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        // macOS writes a hidden ".Screenshot …" temp file, then renames it into place.
        return names.filter { !$0.hasPrefix(".") && Self.imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
    }

    private func scan() {
        for name in imageNames() where !seen.contains(name) {
            seen.insert(name)
            let url = folder.appendingPathComponent(name)
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            // A file moved in from elsewhere keeps its old date — only fresh captures open.
            guard created >= startedAt.addingTimeInterval(-2) else { continue }
            Task { @MainActor [weak self] in
                await Self.waitUntilStable(url)
                self?.onNew(url)
            }
        }
    }

    /// The file may still be growing while screencapture writes it; wait for two equal sizes.
    private static func waitUntilStable(_ url: URL) async {
        var last = -1
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(150))
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            if size > 0 && size == last { return }
            last = size
        }
    }
}
