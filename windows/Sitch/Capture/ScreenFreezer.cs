using System.Windows;
using System.Windows.Interop;
using System.Windows.Media.Imaging;

namespace Sitch.Capture;

/// <summary>GDI BitBlt capture of the desktop at physical pixels (freeze-frame pattern).</summary>
public static class ScreenFreezer
{
    /// <summary>Captures the entire virtual screen. Returns the frozen bitmap + its physical bounds.</summary>
    public static (BitmapSource Bitmap, Int32Rect Bounds) CaptureVirtualScreen()
    {
        var vs = MonitorInfoProvider.GetVirtualScreen();
        return (CapturePhysicalRect(vs), vs);
    }

    /// <summary>Captures an arbitrary rectangle given in physical virtual-screen coordinates.</summary>
    public static BitmapSource CapturePhysicalRect(Int32Rect rect)
    {
        IntPtr screenDc = Native.GetDC(IntPtr.Zero);
        IntPtr memDc = Native.CreateCompatibleDC(screenDc);
        IntPtr hBmp = Native.CreateCompatibleBitmap(screenDc, rect.Width, rect.Height);
        IntPtr old = Native.SelectObject(memDc, hBmp);
        try
        {
            Native.BitBlt(memDc, 0, 0, rect.Width, rect.Height,
                screenDc, rect.X, rect.Y, Native.SRCCOPY | Native.CAPTUREBLT);
            var source = Imaging.CreateBitmapSourceFromHBitmap(
                hBmp, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            source.Freeze();
            return source;
        }
        finally
        {
            Native.SelectObject(memDc, old);
            Native.DeleteObject(hBmp);
            Native.DeleteDC(memDc);
            Native.ReleaseDC(IntPtr.Zero, screenDc);
        }
    }

    /// <summary>
    /// Crops a frozen virtual-screen bitmap to a physical rect (both in virtual-screen space).
    /// Intersects first so overhang on any edge clips instead of sliding the crop window.
    /// </summary>
    public static BitmapSource Crop(BitmapSource frozen, Int32Rect frozenBounds, Int32Rect rect)
    {
        int x1 = Math.Max(rect.X, frozenBounds.X);
        int y1 = Math.Max(rect.Y, frozenBounds.Y);
        int x2 = Math.Min(rect.X + rect.Width, frozenBounds.X + frozenBounds.Width);
        int y2 = Math.Min(rect.Y + rect.Height, frozenBounds.Y + frozenBounds.Height);
        var local = new Int32Rect(
            Math.Clamp(x1 - frozenBounds.X, 0, Math.Max(0, frozen.PixelWidth - 1)),
            Math.Clamp(y1 - frozenBounds.Y, 0, Math.Max(0, frozen.PixelHeight - 1)),
            0, 0);
        local.Width = Math.Clamp(x2 - x1, 1, frozen.PixelWidth - local.X);
        local.Height = Math.Clamp(y2 - y1, 1, frozen.PixelHeight - local.Y);
        var cropped = new CroppedBitmap(frozen, local);
        cropped.Freeze();
        return cropped;
    }
}
