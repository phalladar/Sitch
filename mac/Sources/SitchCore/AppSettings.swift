import Foundation

/// User preferences. Same fields as the Windows `AppSettings` (Mac defaults where the
/// platforms differ), stored as JSON so the two builds stay easy to compare.
public struct AppSettings: Codable, Equatable, Sendable {
    // -- General ------------------------------------------------------------
    /// "System" | "Light" | "Dark"
    public var theme = "System"
    /// Dock icon while an editor is open (Windows: "show editor windows in the taskbar").
    public var showInDock = true
    public var openAtLogin = false

    // -- Capture --------------------------------------------------------------
    public var captureHotkey = "Cmd+Opt+4"
    public var recaptureHotkey = "Cmd+Opt+Shift+4"
    public var defaultSaveFolder = ""
    /// "png" | "jpg" | "pdf" | "tiff"
    public var defaultFormat = "png"
    public var afterShowEditor = true
    /// Every capture lands on the clipboard immediately, ready to paste (on by default).
    public var afterCopy = true
    public var afterSave = false
    /// 0 = off; 3, 5 or 10 seconds.
    public var timerSeconds = 0
    public var watchSystemScreenshots = false
    /// Last region, global screen points (top-left origin of the primary display).
    public var lastRegion: PixelRect?

    // -- Editor window memory (points; 0 = never opened, use size-to-capture) --
    public var editorWidth: Double = 0
    public var editorHeight: Double = 0

    // -- Editor defaults --------------------------------------------------------
    public var defaultColor = "#FF3366"
    public var arrowWidth: Double = 20
    public var shapeWidth: Double = 6
    public var penWidth: Double = 6
    public var highlightWidth: Double = 26
    public var textSize: Double = 28
    public var fontFamily = TextLayout.systemFamily
    /// "pixelate" | "blur" | "block" | "stripes"
    public var obscureStyle = "pixelate"
    public var spotlightDim = 0.55
    public var rememberLastTool = true
    public var lastTool = "arrow"

    public init() {}

    // Tolerant decoding: a missing or mistyped key keeps its default instead of failing the
    // whole file (synthesized Codable would throw and reset every preference).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        let d = AppSettings()
        theme = v(.theme, d.theme)
        showInDock = v(.showInDock, d.showInDock)
        openAtLogin = v(.openAtLogin, d.openAtLogin)
        captureHotkey = v(.captureHotkey, d.captureHotkey)
        recaptureHotkey = v(.recaptureHotkey, d.recaptureHotkey)
        defaultSaveFolder = v(.defaultSaveFolder, d.defaultSaveFolder)
        defaultFormat = v(.defaultFormat, d.defaultFormat)
        afterShowEditor = v(.afterShowEditor, d.afterShowEditor)
        afterCopy = v(.afterCopy, d.afterCopy)
        afterSave = v(.afterSave, d.afterSave)
        timerSeconds = v(.timerSeconds, d.timerSeconds)
        watchSystemScreenshots = v(.watchSystemScreenshots, d.watchSystemScreenshots)
        lastRegion = v(.lastRegion, d.lastRegion)
        editorWidth = v(.editorWidth, d.editorWidth)
        editorHeight = v(.editorHeight, d.editorHeight)
        defaultColor = v(.defaultColor, d.defaultColor)
        arrowWidth = v(.arrowWidth, d.arrowWidth)
        shapeWidth = v(.shapeWidth, d.shapeWidth)
        penWidth = v(.penWidth, d.penWidth)
        highlightWidth = v(.highlightWidth, d.highlightWidth)
        textSize = v(.textSize, d.textSize)
        fontFamily = v(.fontFamily, d.fontFamily)
        obscureStyle = v(.obscureStyle, d.obscureStyle)
        spotlightDim = v(.spotlightDim, d.spotlightDim)
        rememberLastTool = v(.rememberLastTool, d.rememberLastTool)
        lastTool = v(.lastTool, d.lastTool)
    }
}

/// JSON at ~/Library/Application Support/Sitch/settings.json, atomic, best-effort.
public enum SettingsStore {
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sitch", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("settings.json") }

    /// Settings plus whether the file was missing or unreadable (i.e. a fresh install).
    public static func load(from url: URL? = nil) -> (settings: AppSettings, firstRun: Bool) {
        let url = url ?? fileURL
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return (AppSettings(), true) }
        return (s, false)
    }

    public static func save(_ settings: AppSettings, to url: URL? = nil) {
        let url = url ?? fileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(settings).write(to: url, options: .atomic)
        } catch { /* best-effort persistence */ }
    }
}
