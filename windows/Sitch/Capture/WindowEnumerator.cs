using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media.Imaging;

namespace Sitch.Capture;

/// <summary>A pickable top-level window: DWM extended-frame bounds (no drop shadow), physical px.</summary>
public sealed record WindowEntry(IntPtr Hwnd, string Title, Int32Rect Bounds);

public static class WindowEnumerator
{
    /// <summary>Alt-tab-style filtered window list, topmost first (EnumWindows returns z-order).</summary>
    public static List<WindowEntry> GetTopWindows()
    {
        var list = new List<WindowEntry>();
        uint ourPid = (uint)Environment.ProcessId;

        Native.EnumWindows((hwnd, _) =>
        {
            if (!Native.IsWindowVisible(hwnd) || Native.IsIconic(hwnd)) return true;

            Native.GetWindowThreadProcessId(hwnd, out uint pid);
            if (pid == ourPid) return true;

            int len = Native.GetWindowTextLength(hwnd);
            if (len == 0) return true;

            long exStyle = Native.GetWindowLongPtr(hwnd, Native.GWL_EXSTYLE).ToInt64();
            if ((exStyle & Native.WS_EX_TOOLWINDOW) != 0) return true;

            // Cloaked windows (suspended UWP, other virtual desktops) still report visible.
            if (Native.DwmGetWindowAttribute(hwnd, Native.DWMWA_CLOAKED, out int cloaked, sizeof(int)) == 0
                && cloaked != 0) return true;

            if (Native.DwmGetWindowAttribute(hwnd, Native.DWMWA_EXTENDED_FRAME_BOUNDS,
                    out Native.RECT efb, Marshal.SizeOf<Native.RECT>()) != 0)
            {
                if (!Native.GetWindowRect(hwnd, out efb)) return true;
            }

            int w = efb.Right - efb.Left, h = efb.Bottom - efb.Top;
            if (w < 8 || h < 8) return true;

            var buf = new char[len + 1];
            int got = Native.GetWindowText(hwnd, buf, buf.Length);
            list.Add(new WindowEntry(hwnd, new string(buf, 0, got), new Int32Rect(efb.Left, efb.Top, w, h)));
            return true;
        }, IntPtr.Zero);

        return list;
    }

    /// <summary>
    /// Captures a window's own composited content via PrintWindow(PW_RENDERFULLCONTENT),
    /// so partially occluded windows come out clean. Returns null on failure
    /// (caller falls back to cropping the frozen desktop).
    /// </summary>
    public static BitmapSource? CaptureWindow(WindowEntry entry)
    {
        try
        {
            if (!Native.GetWindowRect(entry.Hwnd, out var wr)) return null;
            int fullW = wr.Right - wr.Left, fullH = wr.Bottom - wr.Top;
            if (fullW <= 0 || fullH <= 0) return null;

            // DPI-virtualized windows (system-aware / unaware apps on a scaled monitor):
            // PrintWindow renders at the WINDOW's DPI while our rects are physical, producing
            // shrunken content + black bands. Bail out — the frozen-desktop crop fallback shows
            // the DWM-stretched window exactly as composed on screen.
            uint winDpi = Native.GetDpiForWindow(entry.Hwnd);
            IntPtr hMon = Native.MonitorFromWindow(entry.Hwnd, Native.MONITOR_DEFAULTTONEAREST);
            if (winDpi == 0 ||
                Native.GetDpiForMonitor(hMon, Native.MDT_EFFECTIVE_DPI, out uint monDpi, out _) != 0 ||
                winDpi != monDpi)
                return null;

            IntPtr screenDc = Native.GetDC(IntPtr.Zero);
            IntPtr memDc = Native.CreateCompatibleDC(screenDc);
            IntPtr hBmp = Native.CreateCompatibleBitmap(screenDc, fullW, fullH);
            IntPtr old = Native.SelectObject(memDc, hBmp);
            try
            {
                if (!Native.PrintWindow(entry.Hwnd, memDc, Native.PW_RENDERFULLCONTENT))
                    return null;

                var source = Imaging.CreateBitmapSourceFromHBitmap(
                    hBmp, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());

                // PrintWindow renders at GetWindowRect size; trim the invisible resize borders
                // so we return exactly the visible (extended-frame) bounds.
                int dx = entry.Bounds.X - wr.Left;
                int dy = entry.Bounds.Y - wr.Top;
                var crop = new Int32Rect(
                    Math.Clamp(dx, 0, Math.Max(0, fullW - 1)),
                    Math.Clamp(dy, 0, Math.Max(0, fullH - 1)),
                    Math.Clamp(entry.Bounds.Width, 1, fullW - Math.Clamp(dx, 0, fullW - 1)),
                    Math.Clamp(entry.Bounds.Height, 1, fullH - Math.Clamp(dy, 0, fullH - 1)));
                var cropped = new CroppedBitmap(source, crop);
                cropped.Freeze();
                return cropped;
            }
            finally
            {
                Native.SelectObject(memDc, old);
                Native.DeleteObject(hBmp);
                Native.DeleteDC(memDc);
                Native.ReleaseDC(IntPtr.Zero, screenDc);
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"PrintWindow capture failed: {ex.Message}");
            return null;
        }
    }
}
