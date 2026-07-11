using Microsoft.Win32;

namespace WinSitch.Shell;

/// <summary>Run-at-login via the HKCU Run key (no admin required).</summary>
public static class StartupManager
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ApprovedKey = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
    private const string ValueName = "WinSitch";

    public static bool IsEnabled()
    {
        using var run = Registry.CurrentUser.OpenSubKey(RunKey);
        if (run?.GetValue(ValueName) is not string) return false;

        // Task Manager's enable/disable state lives in StartupApproved: first byte 2/6 = enabled, 3 = disabled.
        using var approved = Registry.CurrentUser.OpenSubKey(ApprovedKey);
        if (approved?.GetValue(ValueName) is byte[] { Length: > 0 } state && (state[0] & 0x01) != 0)
            return false;
        return true;
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
