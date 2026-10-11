/// A global hotkey, stored as e.g. "Cmd+Opt+4" and shown as "⌥⌘4". `keyCode` is the
/// macOS virtual key code (kVK_*) that Carbon's RegisterEventHotKey wants.
public struct HotkeyChord: Equatable, Hashable, Sendable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public var modifiers: Modifiers
    /// Canonical key name: "4", "A", "F5", "Space", …
    public var key: String

    public init(modifiers: Modifiers, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    public var keyCode: Int? { Self.keyCodes[key] }

    /// Storage form, modifiers in the order macOS menus display them.
    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Opt") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Cmd") }
        return (parts + [key]).joined(separator: "+")
    }

    /// Menu-style form: ⌃⌥⇧⌘ then the key.
    public var symbols: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + (Self.keySymbols[key] ?? key)
    }

    public static func parse(_ text: String?) -> HotkeyChord? {
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var mods: Modifiers = []
        var key: String?
        for raw in text.split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) where !raw.isEmpty {
            switch raw.lowercased() {
            case "ctrl", "control", "⌃": mods.insert(.control)
            case "opt", "option", "alt", "⌥": mods.insert(.option)
            case "shift", "⇧": mods.insert(.shift)
            case "cmd", "command", "⌘": mods.insert(.command)
            default: key = canonicalKey(raw)
            }
        }
        guard let key, keyCodes[key] != nil else { return nil }
        return HotkeyChord(modifiers: mods, key: key)
    }

    /// Key name for a virtual key code (used by the settings recorder).
    public static func keyName(forKeyCode code: Int) -> String? {
        keyCodes.first { $0.value == code }?.key
    }

    static func canonicalKey(_ raw: String) -> String? {
        if raw.count == 1 { return raw.uppercased() }
        let lower = raw.lowercased()
        return keyCodes.keys.first { $0.lowercased() == lower }
    }

    /// ANSI-layout virtual key codes (Carbon HIToolbox Events.h).
    static let keyCodes: [String: Int] = [
        "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05, "Z": 0x06, "X": 0x07,
        "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C, "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10,
        "T": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
        "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "O": 0x1F, "U": 0x20,
        "[": 0x21, "I": 0x22, "P": 0x23, "L": 0x25, "J": 0x26, "'": 0x27, "K": 0x28, ";": 0x29,
        "\\": 0x2A, ",": 0x2B, "/": 0x2C, "N": 0x2D, "M": 0x2E, ".": 0x2F, "`": 0x32,
        "Return": 0x24, "Tab": 0x30, "Space": 0x31, "Delete": 0x33, "Escape": 0x35,
        "F1": 0x7A, "F2": 0x78, "F3": 0x63, "F4": 0x76, "F5": 0x60, "F6": 0x61, "F7": 0x62, "F8": 0x64,
        "F9": 0x65, "F10": 0x6D, "F11": 0x67, "F12": 0x6F, "F13": 0x69, "F14": 0x6B, "F15": 0x71,
        "Home": 0x73, "End": 0x77, "PageUp": 0x74, "PageDown": 0x79,
        "Left": 0x7B, "Right": 0x7C, "Down": 0x7D, "Up": 0x7E,
    ]

    static let keySymbols: [String: String] = [
        "Return": "↩", "Tab": "⇥", "Space": "Space", "Delete": "⌫", "Escape": "⎋",
        "Left": "←", "Right": "→", "Up": "↑", "Down": "↓", "PageUp": "⇞", "PageDown": "⇟",
        "Home": "↖", "End": "↘",
    ]

    /// Standalone keys allowed without a modifier (typing letters must never trigger a capture).
    public var isStandaloneKey: Bool { key.hasPrefix("F") && key.count > 1 }
}
