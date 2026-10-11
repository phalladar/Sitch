import AppKit
import SitchCore

/// Design tokens from windows/Sitch/Themes/{Dark,Light}.xaml as appearance-dynamic colors:
/// a view that reads them inside draw(_:) / updateLayer() follows light/dark automatically.
@MainActor
enum Theme {
    static let bar = dynamic(dark: "#1E1E1E", light: "#FAFAFC")
    static let title = dynamic(dark: "#2C2D2E", light: "#F0F0F4")
    static let canvas = dynamic(dark: "#282828", light: "#E4E4E8")
    static let window = dynamic(dark: "#232325", light: "#FAFAFC")
    static let divider = dynamic(dark: "#3A3A3C", light: "#DCDCE1")
    static let text = dynamic(dark: "#F0F0F0", light: "#1D1D1F")
    static let textDim = dynamic(dark: "#98989E", light: "#77777D")
    static let glyph = dynamic(dark: "#C9C9CE", light: "#4A4A50")
    static let tileSel = dynamic(dark: "#45242B", light: "#FFE4EC")
    static let accent = dynamic(dark: "#FF3366", light: "#FF3366")
    static let primary = dynamic(dark: "#007AFF", light: "#007AFF")
    static let field = dynamic(dark: "#2C2D2E", light: "#FFFFFF")
    static let fieldBorder = dynamic(dark: "#48484C", light: "#C8C8CE")
    static let hover = dynamic(dark: "#22FFFFFF", light: "#14000000")
    static let pressed = dynamic(dark: "#33FFFFFF", light: "#22000000")
    static let ghost = dynamic(dark: "#2F2F31", light: "#E6E6EA")

    /// "System" | "Light" | "Dark" → the app-wide appearance (nil follows macOS).
    static func apply(_ setting: String) {
        switch setting {
        case "Light": NSApp.appearance = NSAppearance(named: .aqua)
        case "Dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    private static func dynamic(dark: String, light: String) -> NSColor {
        let d = color(dark), l = color(light)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l
        }
    }

    /// "#RRGGBB" or "#AARRGGBB" (XAML order).
    private static func color(_ hex: String) -> NSColor {
        (RGBAColor(hex: hex) ?? RGBAColor(255, 0, 255)).nsColor
    }
}
