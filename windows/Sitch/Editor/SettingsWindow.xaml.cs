using System.IO;
using System.Media;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Sitch.Core;
using Sitch.Shell;

namespace Sitch.Editor;

public partial class SettingsWindow : Window
{
    private bool _loading = true;

    public SettingsWindow()
    {
        InitializeComponent();
        Icon = new System.Windows.Media.Imaging.BitmapImage(
            new Uri("pack://application:,,,/Assets/sitch.ico"));

        TabGeneral.Checked += (_, _) => ShowPage(PageGeneral);
        TabCapture.Checked += (_, _) => ShowPage(PageCapture);
        TabEditor.Checked += (_, _) => ShowPage(PageEditor);

        var s = App.Settings;

        // General
        (s.Theme switch { "Light" => ThemeLight, "Dark" => ThemeDark, _ => ThemeSystem }).IsChecked = true;
        ThemeSystem.Checked += (_, _) => SetTheme("System");
        ThemeLight.Checked += (_, _) => SetTheme("Light");
        ThemeDark.Checked += (_, _) => SetTheme("Dark");
        ChkTaskbar.IsChecked = s.ShowInTaskbar;
        ChkTaskbar.Click += (_, _) => { s.ShowInTaskbar = ChkTaskbar.IsChecked == true; Save(); };
        ChkLogin.IsChecked = StartupManager.IsEnabled();
        ChkLogin.Click += (_, _) =>
        {
            try
            {
                StartupManager.SetEnabled(ChkLogin.IsChecked == true);
                s.OpenAtLogin = ChkLogin.IsChecked == true;
                Save();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, $"Couldn't update startup entry.\n{ex.Message}", "Sitch");
                ChkLogin.IsChecked = StartupManager.IsEnabled();
            }
        };

        // Capture
        HotkeyBox.Text = s.CaptureHotkey;
        RecaptureBox.Text = s.RecaptureHotkey;
        QuickCopyBox.Text = s.QuickCopyHotkey;
        WireHotkeyRecorder(HotkeyBox, App.HkCapture, chord => { s.CaptureHotkey = chord; Save(); });
        WireHotkeyRecorder(RecaptureBox, App.HkRecapture, chord => { s.RecaptureHotkey = chord; Save(); });
        WireHotkeyRecorder(QuickCopyBox, App.HkQuickCopy, chord => { s.QuickCopyHotkey = chord; Save(); });

        FolderBox.Text = s.DefaultSaveFolder;
        FolderBox.LostFocus += (_, _) => { s.DefaultSaveFolder = FolderBox.Text.Trim(); Save(); };
        BtnBrowse.Click += (_, _) => BrowseFolder();

        foreach (var f in Export.Exporters.Formats) FormatCombo.Items.Add(f);
        FormatCombo.SelectedItem = s.DefaultFormat;
        FormatCombo.SelectionChanged += (_, _) =>
        {
            if (!_loading && FormatCombo.SelectedItem is string f) { s.DefaultFormat = f; Save(); }
        };

        ChkAfterShow.IsChecked = s.AfterShowEditor;
        ChkAfterCopy.IsChecked = s.AfterCopy;
        ChkAfterSave.IsChecked = s.AfterSave;
        ChkAfterShow.Click += (_, _) => { s.AfterShowEditor = ChkAfterShow.IsChecked == true; Save(); };
        ChkAfterCopy.Click += (_, _) => { s.AfterCopy = ChkAfterCopy.IsChecked == true; Save(); };
        ChkAfterSave.Click += (_, _) => { s.AfterSave = ChkAfterSave.IsChecked == true; Save(); };

        foreach (var t in new[] { "Off", "3 s", "5 s", "10 s" }) TimerCombo.Items.Add(t);
        TimerCombo.SelectedIndex = s.TimerSeconds switch { 3 => 1, 5 => 2, 10 => 3, _ => 0 };
        TimerCombo.SelectionChanged += (_, _) =>
        {
            if (_loading) return;
            s.TimerSeconds = TimerCombo.SelectedIndex switch { 1 => 3, 2 => 5, 3 => 10, _ => 0 };
            Save();
        };

        ChkWatch.IsChecked = s.WatchSystemScreenshots;
        ChkWatch.Click += (_, _) =>
        {
            s.WatchSystemScreenshots = ChkWatch.IsChecked == true;
            Save();
            App.Current.UpdateScreenshotWatcher();
        };

        // Editor
        ChkRememberTool.IsChecked = s.RememberLastTool;
        ChkRememberTool.Click += (_, _) => { s.RememberLastTool = ChkRememberTool.IsChecked == true; Save(); };
        ArrowWidthBox.Text = s.ArrowWidth.ToString();
        ArrowWidthBox.LostFocus += (_, _) =>
        {
            if (double.TryParse(ArrowWidthBox.Text, out var v)) { s.ArrowWidth = Math.Clamp(v, 1, 200); Save(); }
            ArrowWidthBox.Text = s.ArrowWidth.ToString();
        };
        TextSizeBox.Text = s.TextSize.ToString();
        TextSizeBox.LostFocus += (_, _) =>
        {
            if (double.TryParse(TextSizeBox.Text, out var v)) { s.TextSize = Math.Clamp(v, 6, 300); Save(); }
            TextSizeBox.Text = s.TextSize.ToString();
        };
        DimSlider.Value = s.SpotlightDim * 100;
        DimLabel.Text = $"{Math.Round(DimSlider.Value)}%";
        DimSlider.ValueChanged += (_, _) =>
        {
            DimLabel.Text = $"{Math.Round(DimSlider.Value)}%";
            if (_loading) return;
            s.SpotlightDim = DimSlider.Value / 100.0;
            Save();
        };

        _loading = false;
    }

    private void ShowPage(UIElement page)
    {
        PageGeneral.Visibility = ReferenceEquals(page, PageGeneral) ? Visibility.Visible : Visibility.Collapsed;
        PageCapture.Visibility = ReferenceEquals(page, PageCapture) ? Visibility.Visible : Visibility.Collapsed;
        PageEditor.Visibility = ReferenceEquals(page, PageEditor) ? Visibility.Visible : Visibility.Collapsed;
    }

    private void SetTheme(string theme)
    {
        if (_loading) return;
        App.Settings.Theme = theme;
        Save();
        ThemeManager.Apply(theme);
    }

    private static void Save() => SettingsStore.Save(App.Settings);

    /// <summary>Click the box, press a combination, done. Esc reverts, Backspace also reverts.
    /// A chord another Sitch action already owns is refused and recording continues.</summary>
    private static void WireHotkeyRecorder(TextBox box, int slotId, Action<string> commit)
    {
        string previous = box.Text;
        bool recording = false;
        box.GotKeyboardFocus += (_, _) =>
        {
            previous = box.Text;
            box.Text = "Press keys…";
            recording = true;
            // Registered hotkeys swallow their chord, so it would fire a capture instead of
            // reaching this box.
            App.Current.UnregisterHotkeys();
        };
        box.LostKeyboardFocus += (_, _) =>
        {
            if (recording) box.Text = previous;
            recording = false;
            App.Current.RegisterHotkeys();
        };
        box.PreviewKeyDown += (_, e) =>
        {
            e.Handled = true;
            var key = e.Key == Key.System ? e.SystemKey : e.Key;
            if (key is Key.Escape or Key.Back)
            {
                box.Text = previous;
                Keyboard.ClearFocus();
                return;
            }
            if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt
                or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin)
                return; // wait for the terminal key

            var chord = new HotkeyChord(Keyboard.Modifiers, key);
            // Bare letters/digits would fire constantly while typing elsewhere; require a modifier
            // except for keys that are conventionally standalone.
            bool standalone = key is Key.Snapshot or (>= Key.F1 and <= Key.F12);
            if (chord.Modifiers == ModifierKeys.None && !standalone) return;
            if (App.HotkeyOwner(chord, slotId) is { } owner)
            {
                SystemSounds.Beep.Play();
                box.Text = $"{chord} is used by {owner}";
                return;
            }

            box.Text = chord.ToString();
            previous = box.Text;
            recording = false;
            commit(chord.ToString());
            Keyboard.ClearFocus();
        };
    }

    private void BrowseFolder()
    {
        var dlg = new Microsoft.Win32.OpenFolderDialog();
        if (Directory.Exists(FolderBox.Text)) dlg.InitialDirectory = FolderBox.Text;
        if (dlg.ShowDialog(this) == true)
        {
            FolderBox.Text = dlg.FolderName;
            App.Settings.DefaultSaveFolder = dlg.FolderName;
            Save();
        }
    }
}
