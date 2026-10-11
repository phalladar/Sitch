using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Sitch.Core;

/// <summary>A rectangle in physical (virtual-screen) pixels; JSON-friendly.</summary>
public record struct PixelRect(int X, int Y, int Width, int Height);

public class AppSettings
{
    // -- General ------------------------------------------------------------
    /// <summary>"System" | "Light" | "Dark"</summary>
    public string Theme { get; set; } = "System";
    public bool ShowTrayIcon { get; set; } = true;
    public bool ShowInTaskbar { get; set; } = true;   // editor windows on the taskbar
    public bool OpenAtLogin { get; set; }

    // -- Capture --------------------------------------------------------------
    public string CaptureHotkey { get; set; } = "Ctrl+Alt+4";
    public string RecaptureHotkey { get; set; } = "Ctrl+Alt+Shift+4";
    public string DefaultSaveFolder { get; set; } = "";
    /// <summary>"png" | "jpg" | "pdf" | "tiff"</summary>
    public string DefaultFormat { get; set; } = "png";
    public bool AfterShowEditor { get; set; } = true;
    /// <summary>Every capture lands on the clipboard immediately, ready to paste (on by default).</summary>
    public bool AfterCopy { get; set; } = true;
    public bool AfterSave { get; set; }
    /// <summary>0 = off; 3, 5 or 10 seconds.</summary>
    public int TimerSeconds { get; set; }
    public bool WatchSystemScreenshots { get; set; }
    public PixelRect? LastRegion { get; set; }

    // -- Editor window memory (DIPs; 0 = never opened, use size-to-capture) ------
    public double EditorWidth { get; set; }
    public double EditorHeight { get; set; }
    public bool EditorMaximized { get; set; }

    // -- Editor defaults --------------------------------------------------------
    public string DefaultColor { get; set; } = "#FF3366";
    public double ArrowWidth { get; set; } = 20;
    public double ShapeWidth { get; set; } = 6;
    public double PenWidth { get; set; } = 6;
    public double HighlightWidth { get; set; } = 26;
    public double TextSize { get; set; } = 28;
    public string FontFamily { get; set; } = "Segoe UI";
    /// <summary>"Pixelate" | "Blur" | "Block" | "Stripes"</summary>
    public string ObscureStyle { get; set; } = "Pixelate";
    public double SpotlightDim { get; set; } = 0.55;
    public bool RememberLastTool { get; set; } = true;
    public string LastTool { get; set; } = "Arrow";
}

public static class SettingsStore
{
    public static string Dir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Sitch");

    private static string FilePath => Path.Combine(Dir, "settings.json");

    // Pre-rebrand builds (WinSitch ≤0.1.2) kept settings under %APPDATA%\WinSitch.
    private static string LegacyFilePath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "WinSitch", "settings.json");

    /// <summary>True when Load() found no settings file — i.e. a fresh install.</summary>
    public static bool FirstRun { get; private set; }

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
    };

    public static AppSettings Load()
    {
        try
        {
            if (!File.Exists(FilePath) && File.Exists(LegacyFilePath))
            {
                Directory.CreateDirectory(Dir);
                File.Copy(LegacyFilePath, FilePath); // copy, not move: an old WinSitch.exe may still run
            }
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath), Options) ?? new();
        }
        catch { /* corrupted settings: fall back to defaults */ }
        FirstRun = true;
        return new AppSettings();
    }

    public static void Save(AppSettings settings)
    {
        try
        {
            Directory.CreateDirectory(Dir);
            var tmp = FilePath + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(settings, Options));
            File.Move(tmp, FilePath, overwrite: true);
        }
        catch { /* best-effort persistence */ }
    }
}
