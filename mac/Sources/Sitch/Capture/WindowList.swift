import AppKit

/// A pickable top-level window: Quartz frame (global points, top-left origin), no shadow.
struct WindowEntry {
    let id: CGWindowID
    let title: String
    let frame: CGRect
}

/// Counterpart of WindowEnumerator.GetTopWindows: on-screen app windows, front to back.
enum WindowList {
    static func topWindows() -> [WindowEntry] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let ourPID = ProcessInfo.processInfo.processIdentifier
        return info.compactMap { w in
            // Layer 0 = ordinary app windows; menu bar, Dock, overlays and panels sit above.
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != ourPID,
                  let owner = w[kCGWindowOwnerName as String] as? String, !owner.isEmpty,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  frame.width >= 8, frame.height >= 8
            else { return nil }
            let name = w[kCGWindowName as String] as? String ?? ""
            return WindowEntry(id: id, title: name.isEmpty ? owner : name, frame: frame)
        }
    }
}
