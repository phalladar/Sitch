using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;
using WinSitch.Capture;
using WinSitch.Core;
using WinSitch.Editor;
using WinSitch.Export;
using WinSitch.Shell;

namespace WinSitch;

public partial class App : Application
{
    public static AppSettings Settings { get; private set; } = new();
    public static new App Current => (App)Application.Current;

    public const int HkCapture = 1;
    public const int HkRecapture = 2;

    private SingleInstance? _instance;
    private TrayController? _tray;
    private HotkeyManager? _hotkeys;
    private CaptureController? _capture;
    private ScreenshotWatcher? _watcher;

    public CaptureController Capture => _capture!;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Self-contained render+exit mode; never needs (or should touch) the singleton.
        foreach (var arg in e.Args)
        {
            if (arg.StartsWith("--shot-region=", StringComparison.Ordinal))
            {
                Settings = SettingsStore.Load();
                DemoMode.RenderRegionShot(arg["--shot-region=".Length..]);
                Shutdown();
                return;
            }
        }

        _instance = SingleInstance.TryAcquire(OnIpcMessage);
        if (_instance is null)
        {
            // Another WinSitch is running: hand our args to it and bow out.
            SingleInstance.SendToPrimary(e.Args);
            Shutdown();
            return;
        }

        Settings = SettingsStore.Load();
        ThemeManager.Apply(Settings.Theme);

        _capture = new CaptureController();
        _hotkeys = new HotkeyManager();
        _hotkeys.Pressed += OnHotkey;
        RegisterHotkeys();

        _tray = new TrayController();
        UpdateScreenshotWatcher();

        HandleArgs(e.Args);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _watcher?.Dispose();
        _hotkeys?.Dispose();
        _tray?.Dispose();
        _instance?.Dispose();
        base.OnExit(e);
    }

    // ---- IPC from secondary instances --------------------------------------

    private void OnIpcMessage(string message)
    {
        Dispatcher.Invoke(() =>
        {
            if (message.StartsWith("OPEN ", StringComparison.Ordinal))
                OpenImageFile(message[5..]);
            else if (message == "CAPTURE")
                CaptureRegion();
            else if (message == "SETTINGS")
                ShowSettings();
            else if (message == "FOCUS")
                FocusAnyEditor();
        });
    }

    private void HandleArgs(string[] args)
    {
        foreach (var arg in args)
        {
            switch (arg)
            {
                case "--demo": DemoMode.OpenEditorDemo(); break;
                case "--demo-crop": DemoMode.OpenEditorDemo(cropMode: true); break;
                case "--demo-light": DemoMode.OpenEditorDemo(lightTheme: true); break;
                case "--settings": ShowSettings(); break;
                case "--capture": CaptureRegion(); break;
                default:
                    if (File.Exists(arg)) OpenImageFile(arg);
                    break;
            }
        }
    }

    // ---- Hotkeys ------------------------------------------------------------

    public void RegisterHotkeys()
    {
        if (_hotkeys is null) return;
        _hotkeys.UnregisterAll();
        if (HotkeyChord.TryParse(Settings.CaptureHotkey, out var cap) &&
            !_hotkeys.Register(HkCapture, cap))
            NotifyPopup.Show($"Capture hotkey {cap} is in use by another app.");
        if (HotkeyChord.TryParse(Settings.RecaptureHotkey, out var re) &&
            !_hotkeys.Register(HkRecapture, re))
            NotifyPopup.Show($"Recapture hotkey {re} is in use by another app.");
    }

    private void OnHotkey(int id)
    {
        switch (id)
        {
            case HkCapture: CaptureRegion(); break;
            case HkRecapture: RecaptureLast(); break;
        }
    }

    // ---- Capture entry points ------------------------------------------------

    public void CaptureRegion() => StartCapture(CaptureMode.Region);
    public void CaptureWindow() => StartCapture(CaptureMode.Window);

    public void CaptureFullScreen(int monitorIndex)
    {
        RunWithTimer(() =>
        {
            var result = _capture!.CaptureMonitor(monitorIndex);
            if (result is not null) RouteCapture(result);
        });
    }

    public void RecaptureLast()
    {
        if (Settings.LastRegion is { Width: > 0, Height: > 0 } r)
        {
            RunWithTimer(() =>
            {
                var result = _capture!.CaptureRegionRect(r);
                if (result is not null) RouteCapture(result);
            });
        }
        else CaptureRegion();
    }

    /// <summary>Interactive region capture that skips the editor entirely (v1.3 quick capture).</summary>
    public void QuickCapture(bool toClipboard)
    {
        _capture!.StartInteractive(CaptureMode.Region, result =>
        {
            RememberRegion(result);
            if (toClipboard)
            {
                if (ClipboardHelper.CopyImage(result.Bitmap))
                {
                    NotifyPopup.Show("Copied to clipboard.", result.Bitmap);
                }
                else
                {
                    // Clipboard held by another app — don't lose the frame.
                    var fallback = Exporters.QuickSave(result.Bitmap);
                    NotifyPopup.Show($"Clipboard busy — saved {Path.GetFileName(fallback)} instead.", result.Bitmap);
                }
            }
            else
            {
                var path = Exporters.QuickSave(result.Bitmap);
                NotifyPopup.Show($"Saved {Path.GetFileName(path)}", result.Bitmap);
            }
        });
    }

    private void StartCapture(CaptureMode mode)
    {
        RunWithTimer(() => _capture!.StartInteractive(mode, RouteCapture));
    }

    private void RunWithTimer(Action action)
    {
        int secs = Settings.TimerSeconds;
        if (secs is 3 or 5 or 10)
            CountdownPopup.Run(secs, action);
        else
            action();
    }

    /// <summary>Applies the configured after-capture actions (show / copy / save, any combo).</summary>
    private void RouteCapture(CaptureResult result)
    {
        RememberRegion(result);
        bool any = false;
        if (Settings.AfterCopy)
        {
            if (ClipboardHelper.CopyImage(result.Bitmap))
            {
                NotifyPopup.Show("Copied to clipboard.", result.Bitmap);
                any = true; // a failed copy must NOT count — the editor fallback keeps the frame
            }
            else
            {
                NotifyPopup.Show("Clipboard is busy — opening the editor instead.");
            }
        }
        if (Settings.AfterSave)
        {
            var path = Exporters.QuickSave(result.Bitmap);
            NotifyPopup.Show($"Saved {Path.GetFileName(path)}", result.Bitmap);
            any = true;
        }
        if (Settings.AfterShowEditor || !any)
            OpenEditor(result.Bitmap, "Untitled", result.SourceScreenRect);
    }

    private void RememberRegion(CaptureResult result)
    {
        if (result.Kind == CaptureMode.Region && result.PhysicalRect is { } r)
        {
            Settings.LastRegion = r;
            SettingsStore.Save(Settings);
        }
    }

    // ---- Windows -------------------------------------------------------------

    public void OpenEditor(BitmapSource bitmap, string title, PixelRect? sourceRect = null)
    {
        var win = new EditorWindow(bitmap, title, sourceRect);
        win.Show();
        win.Activate();
    }

    public void OpenImageFile(string path)
    {
        try
        {
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.UriSource = new Uri(Path.GetFullPath(path));
            bmp.EndInit();
            bmp.Freeze();
            OpenEditor(bmp, Path.GetFileNameWithoutExtension(path));
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Couldn't open {path}\n\n{ex.Message}", "WinSitch",
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private SettingsWindow? _settingsWindow;

    public void ShowSettings()
    {
        if (_settingsWindow is { IsLoaded: true })
        {
            _settingsWindow.Activate();
            return;
        }
        _settingsWindow = new SettingsWindow();
        _settingsWindow.Show();
    }

    private void FocusAnyEditor()
    {
        foreach (Window w in Windows)
            if (w is EditorWindow) { w.Activate(); return; }
    }

    public void UpdateScreenshotWatcher()
    {
        _watcher?.Dispose();
        _watcher = Settings.WatchSystemScreenshots ? new ScreenshotWatcher(OpenImageFile) : null;
    }

    public void QuitRequested()
    {
        // Give every dirty editor a chance to veto — and close without re-prompting.
        foreach (Window w in Windows.Cast<Window>().ToList())
        {
            if (w is EditorWindow ed)
            {
                if (!ed.ConfirmClose()) return;
                ed.CloseWithoutPrompt();
            }
            else
            {
                w.Close();
            }
        }
        Shutdown();
    }
}
