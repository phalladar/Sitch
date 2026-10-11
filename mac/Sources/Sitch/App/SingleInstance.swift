import AppKit

/// One Sitch per user. Launch Services already reuses a running bundled app for `open` and
/// Finder launches; this covers running the binary directly (CLI flags like `--demo`), which
/// would otherwise start a second menu-bar app. Args travel over a distributed notification
/// (Windows: named mutex + named pipe).
@MainActor
enum SingleInstance {
    private static let name = Notification.Name("io.github.phalladar.Sitch.forwardArgs")

    /// True when another instance exists and received our args — the caller should exit.
    static func forwardToRunningInstance(_ args: [String]) -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false } // unbundled dev binary
        let me = ProcessInfo.processInfo.processIdentifier
        guard let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.processIdentifier != me }) else { return false }
        // Relative paths mean nothing to the other process.
        let resolved = args.map { arg in
            arg.hasPrefix("--") ? arg : URL(fileURLWithPath: arg).standardizedFileURL.path
        }
        DistributedNotificationCenter.default().postNotificationName(
            name, object: nil, userInfo: ["args": resolved, "pid": Int(other.processIdentifier)],
            deliverImmediately: true)
        return true
    }

    static func listen(_ handler: @escaping @MainActor ([String]) -> Void) {
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { note in
            guard note.userInfo?["pid"] as? Int == me else { return }
            let args = note.userInfo?["args"] as? [String] ?? []
            MainActor.assumeIsolated { handler(args) }
        }
    }
}
