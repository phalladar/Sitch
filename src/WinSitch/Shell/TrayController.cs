using System.Windows;
using System.Windows.Controls;
using H.NotifyIcon;
using WinSitch.Capture;

namespace WinSitch.Shell;

/// <summary>System-tray presence: icon + context menu, the app's home base.</summary>
public sealed class TrayController : IDisposable
{
    private readonly TaskbarIcon _icon;

    public TrayController()
    {
        _icon = new TaskbarIcon
        {
            ToolTipText = "WinSitch — Capture. Annotate. Share.",
            IconSource = new System.Windows.Media.Imaging.BitmapImage(
                new Uri("pack://application:,,,/Assets/winsitch.ico")),
            ContextMenu = BuildMenu(),
        };
        _icon.TrayLeftMouseUp += (_, _) => App.Current.CaptureRegion();
        _icon.ForceCreate();
    }

    private ContextMenu BuildMenu()
    {
        var menu = new ContextMenu();

        var captureItem = Item($"Capture Region\t{App.Settings.CaptureHotkey}", () => App.Current.CaptureRegion());
        menu.Items.Add(captureItem);
        menu.Items.Add(Item("Capture Window", () => App.Current.CaptureWindow()));

        var full = new MenuItem { Header = "Capture Full Screen" };
        full.SubmenuOpened += (_, _) =>
        {
            full.Items.Clear();
            var monitors = MonitorInfoProvider.GetMonitors();
            for (int i = 0; i < monitors.Count; i++)
            {
                int idx = i;
                var m = monitors[i];
                full.Items.Add(Item($"Display {i + 1} ({m.Bounds.Width}×{m.Bounds.Height}){(m.IsPrimary ? " — primary" : "")}",
                    () => App.Current.CaptureFullScreen(idx)));
            }
        };
        full.Items.Add(new MenuItem { Header = "…" }); // placeholder so the submenu arrow shows
        menu.Items.Add(full);

        var recaptureItem = Item($"Recapture Last Region\t{App.Settings.RecaptureHotkey}", () => App.Current.RecaptureLast());
        menu.Items.Add(recaptureItem);
        // Hotkeys are rebindable in Settings — refresh the labels every time the menu opens.
        menu.Opened += (_, _) =>
        {
            captureItem.Header = $"Capture Region\t{App.Settings.CaptureHotkey}";
            recaptureItem.Header = $"Recapture Last Region\t{App.Settings.RecaptureHotkey}";
        };
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("Quick Capture → Clipboard", () => App.Current.QuickCapture(toClipboard: true)));
        menu.Items.Add(Item("Quick Capture → File", () => App.Current.QuickCapture(toClipboard: false)));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("Open Image…", OpenImageDialog));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("Settings…", () => App.Current.ShowSettings()));
        menu.Items.Add(Item("About WinSitch", ShowAbout));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("Quit WinSitch", () => App.Current.QuitRequested()));
        return menu;
    }

    private static MenuItem Item(string header, Action action)
    {
        var mi = new MenuItem { Header = header };
        mi.Click += (_, _) => action();
        return mi;
    }

    private static void OpenImageDialog()
    {
        var dlg = new Microsoft.Win32.OpenFileDialog
        {
            Filter = "Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff;*.webp|All files|*.*",
        };
        if (dlg.ShowDialog() == true)
            App.Current.OpenImageFile(dlg.FileName);
    }

    private static void ShowAbout()
    {
        MessageBox.Show(
            "WinSitch 0.1.0\n\nSkitch-style screenshot annotation for Windows.\nCapture. Annotate. Share.\n\n" +
            "MIT License — © 2026 Josh Auriemma\ngithub.com/phalladar/winsitch",
            "About WinSitch", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    public void Dispose() => _icon.Dispose();
}
