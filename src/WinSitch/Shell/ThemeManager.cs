using System.Windows;
using Microsoft.Win32;

namespace WinSitch.Shell;

public static class ThemeManager
{
    public static bool IsDark { get; private set; } = true;
    public static event Action? Changed;

    /// <summary>theme: "System" | "Light" | "Dark"</summary>
    public static void Apply(string theme)
    {
        bool dark = theme switch
        {
            "Light" => false,
            "Dark" => true,
            _ => SystemPrefersDark(),
        };
        IsDark = dark;
        var uri = new Uri($"Themes/{(dark ? "Dark" : "Light")}.xaml", UriKind.Relative);
        Application.Current.Resources.MergedDictionaries[0] = new ResourceDictionary { Source = uri };
        Changed?.Invoke();
    }

    private static bool SystemPrefersDark()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int v && v == 0;
        }
        catch { return true; }
    }
}
