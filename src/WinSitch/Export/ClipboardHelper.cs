using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace WinSitch.Export;

public static class ClipboardHelper
{
    /// <summary>
    /// Writes the image in three formats for maximum paste compatibility:
    /// a raw "PNG" stream (Chromium/Office, preserves transparency), plus CF_BITMAP
    /// flattened onto white (Paint/legacy; Windows synthesizes CF_DIB from it).
    /// Full-size 1x pixels — high-DPI captures paste at native resolution.
    /// </summary>
    public static bool CopyImage(BitmapSource bmp)
    {
        var data = new DataObject();

        var png = new MemoryStream();
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bmp));
        encoder.Save(png);
        png.Position = 0;
        data.SetData("PNG", png, autoConvert: false);

        data.SetImage(FlattenToWhite(bmp));

        // Clipboard can be briefly held by managers (Win+V, Ditto) → CLIPBRD_E_CANT_OPEN; retry.
        for (int attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                Clipboard.SetDataObject(data, copy: true);
                return true;
            }
            catch (COMException)
            {
                Thread.Sleep(70);
            }
        }
        return false;
    }

    /// <summary>CF_DIB has no alpha: composite onto white ourselves rather than letting it go black.</summary>
    public static BitmapSource FlattenToWhite(BitmapSource bmp)
    {
        if (bmp.Format == PixelFormats.Bgr24 || bmp.Format == PixelFormats.Bgr32)
            return bmp;
        var dv = new DrawingVisual();
        using (var dc = dv.RenderOpen())
        {
            var rect = new Rect(0, 0, bmp.PixelWidth, bmp.PixelHeight);
            dc.DrawRectangle(Brushes.White, null, rect);
            dc.DrawImage(bmp, rect);
        }
        var rtb = new RenderTargetBitmap(bmp.PixelWidth, bmp.PixelHeight, 96, 96, PixelFormats.Pbgra32);
        rtb.Render(dv);
        rtb.Freeze();
        return rtb;
    }
}
