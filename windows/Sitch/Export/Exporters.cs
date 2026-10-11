using System.IO;
using System.Windows.Media.Imaging;
using PdfSharp.Drawing;
using PdfSharp.Pdf;

namespace Sitch.Export;

public static class Exporters
{
    public static readonly string[] Formats = ["png", "jpg", "pdf", "tiff"];

    /// <summary>Encodes and writes the bitmap in the format implied by the path's extension.</summary>
    public static void Save(BitmapSource bmp, string path)
    {
        var ext = Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        if (ext == "pdf")
        {
            SavePdf(bmp, path);
            return;
        }
        BitmapEncoder encoder = ext switch
        {
            "jpg" or "jpeg" => new JpegBitmapEncoder { QualityLevel = 92 },
            "tif" or "tiff" => new TiffBitmapEncoder(),
            _ => new PngBitmapEncoder(),
        };
        // JPEG has no alpha channel: flatten explicitly instead of getting a black background.
        var source = ext is "jpg" or "jpeg" ? ClipboardHelper.FlattenToWhite(bmp) : bmp;
        encoder.Frames.Add(BitmapFrame.Create(source));
        using var fs = File.Create(path);
        encoder.Save(fs);
    }

    /// <summary>
    /// Single-page PDF with the bitmap at exact physical size. PDF pages are sized in
    /// points (1pt = 1/72"), so page size = pixels * 72 / 96 — never rely on the
    /// bitmap's embedded resolution metadata.
    /// </summary>
    private static void SavePdf(BitmapSource bmp, string path)
    {
        double wPt = bmp.PixelWidth * 72.0 / 96.0;
        double hPt = bmp.PixelHeight * 72.0 / 96.0;
        using var doc = new PdfDocument();
        doc.Info.Title = Path.GetFileNameWithoutExtension(path);
        doc.Info.Creator = "Sitch";
        var page = doc.AddPage();
        page.Width = XUnit.FromPoint(wPt);
        page.Height = XUnit.FromPoint(hPt);
        using var gfx = XGraphics.FromPdfPage(page);
        using var ximg = XImage.FromBitmapSource(ClipboardHelper.FlattenToWhite(bmp));
        gfx.DrawImage(ximg, 0, 0, wPt, hPt);
        doc.Save(path);
    }

    /// <summary>Quick-capture save: default folder (or Pictures\Sitch), timestamped name.</summary>
    public static string QuickSave(BitmapSource bmp)
    {
        var folder = App.Settings.DefaultSaveFolder;
        if (string.IsNullOrWhiteSpace(folder) || !Directory.Exists(folder))
        {
            folder = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Sitch");
            Directory.CreateDirectory(folder);
        }
        var fmt = App.Settings.DefaultFormat is "jpg" or "tiff" or "pdf" ? App.Settings.DefaultFormat : "png";
        var baseName = $"Sitch {DateTime.Now:yyyy-MM-dd 'at' HH.mm.ss}";
        var path = Path.Combine(folder, $"{baseName}.{fmt}");
        // Two captures in the same second must not overwrite each other.
        for (int n = 2; File.Exists(path); n++)
            path = Path.Combine(folder, $"{baseName} ({n}).{fmt}");
        Save(bmp, path);
        return path;
    }
}
