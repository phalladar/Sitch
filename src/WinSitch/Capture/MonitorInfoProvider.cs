using System.Windows;

namespace WinSitch.Capture;

/// <summary>One physical display: bounds + work area in physical (virtual-screen) pixels + effective DPI scale.</summary>
public sealed record MonitorData(IntPtr Handle, Int32Rect Bounds, Int32Rect WorkArea, bool IsPrimary, double Scale);

public static class MonitorInfoProvider
{
    public static IReadOnlyList<MonitorData> GetMonitors()
    {
        var list = new List<MonitorData>();
        Native.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero,
            (IntPtr hMon, IntPtr _, ref Native.RECT _, IntPtr _) =>
            {
                var mi = new Native.MONITORINFOEX { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<Native.MONITORINFOEX>() };
                if (Native.GetMonitorInfo(hMon, ref mi))
                {
                    double scale = 1.0;
                    if (Native.GetDpiForMonitor(hMon, Native.MDT_EFFECTIVE_DPI, out uint dpiX, out _) == 0)
                        scale = dpiX / 96.0;
                    list.Add(new MonitorData(
                        hMon,
                        new Int32Rect(mi.rcMonitor.Left, mi.rcMonitor.Top,
                            mi.rcMonitor.Right - mi.rcMonitor.Left, mi.rcMonitor.Bottom - mi.rcMonitor.Top),
                        new Int32Rect(mi.rcWork.Left, mi.rcWork.Top,
                            mi.rcWork.Right - mi.rcWork.Left, mi.rcWork.Bottom - mi.rcWork.Top),
                        (mi.dwFlags & Native.MONITORINFOF_PRIMARY) != 0,
                        scale));
                }
                return true;
            }, IntPtr.Zero);
        // Primary first, then left-to-right: stable ordering for the tray menu.
        return list.OrderByDescending(m => m.IsPrimary).ThenBy(m => m.Bounds.X).ToList();
    }

    public static Int32Rect GetVirtualScreen() => new(
        Native.GetSystemMetrics(Native.SM_XVIRTUALSCREEN),
        Native.GetSystemMetrics(Native.SM_YVIRTUALSCREEN),
        Native.GetSystemMetrics(Native.SM_CXVIRTUALSCREEN),
        Native.GetSystemMetrics(Native.SM_CYVIRTUALSCREEN));
}
