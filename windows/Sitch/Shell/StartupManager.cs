using Microsoft.Win32;

namespace Sitch.Shell;

/// <summary>Run-at-login via the HKCU Run key (no admin required).</summary>
public static class StartupManager
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ApprovedKey = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
    private const string ValueName = "Sitch";
    private const string LegacyValueName = "WinSitch";

    public static bool IsEnabled()
    {
        using var run = Registry.CurrentUser.OpenSubKey(RunKey);
        if (run?.GetValue(ValueName) is not string) return false;

        using var approved = Registry.CurrentUser.OpenSubKey(ApprovedKey);
        return !IsDisabled(approved, ValueName);
    }

    // Task Manager's enable/disable state lives in StartupApproved: first byte 2/6 = enabled, 3 = disabled.
    private static bool IsDisabled(RegistryKey? approved, string name) =>
        approved?.GetValue(name) is byte[] { Length: > 0 } state && (state[0] & 0x01) != 0;

    /// <summary>
    /// Pre-rebrand builds registered "WinSitch" → WinSitch.exe. Drop that entry and, if it was
    /// enabled, re-register under the new name so open-at-login survives the upgrade.
    /// </summary>
    public static void MigrateLegacy()
    {
        try
        {
            using var run = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
            if (run?.GetValue(LegacyValueName) is not string) return;
            using var approved = Registry.CurrentUser.OpenSubKey(ApprovedKey, writable: true);
            var wasEnabled = !IsDisabled(approved, LegacyValueName);
            run.DeleteValue(LegacyValueName, throwOnMissingValue: false);
            approved?.DeleteValue(LegacyValueName, throwOnMissingValue: false);
            if (wasEnabled) SetEnabled(true);
        }
        catch { /* best-effort, like settings persistence */ }
    }

    public static void SetEnabled(bool enabled)
    {
        using var run = Registry.CurrentUser.CreateSubKey(RunKey);
        if (enabled)
        {
            var exe = Environment.ProcessPath ?? "";
            run.SetValue(ValueName, $"\"{exe}\"");
            // Clear a stale "disabled" flag so the toggle takes effect.
            using var approved = Registry.CurrentUser.OpenSubKey(ApprovedKey, writable: true);
            approved?.DeleteValue(ValueName, throwOnMissingValue: false);
        }
        else
        {
            run.DeleteValue(ValueName, throwOnMissingValue: false);
        }
    }
}
