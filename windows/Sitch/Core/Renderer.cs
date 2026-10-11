using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Sitch.Core;

/// <summary>
/// Composition pipeline (canvas preview and export share it):
/// base → obscure effects → spotlight dim → vector marks.
/// Effects flatten before shapes, so blur never smears an annotation.
/// </summary>
public static class Renderer
{
    /// <summary>Draws the full document in doc-pixel space (caller applies zoom/crop transforms).</summary>
    public static void Draw(DrawingContext dc, Document doc, bool forExport, Annotation? skip = null)
    {
        var ctx = new RenderContext { Base = doc.Base, BaseVersion = doc.BaseVersion, ForExport = forExport };
        var full = new Rect(0, 0, doc.Width, doc.Height);

        dc.DrawImage(doc.Base, full);

        foreach (var a in doc.Annotations)
            if (a.IsEffect && !a.IsSpotlight && !ReferenceEquals(a, skip))
                a.Render(dc, ctx);

        var spots = doc.Annotations.OfType<SpotlightAnnotation>()
            .Where(s => !ReferenceEquals(s, skip) && s.Rect is { Width: > 1, Height: > 1 }).ToList();
        if (spots.Count > 0)
        {
            Geometry dim = new RectangleGeometry(full);
            foreach (var s in spots)
                dim = new CombinedGeometry(GeometryCombineMode.Exclude, dim, new RectangleGeometry(s.Rect));
            double opacity = Math.Clamp(App.Settings.SpotlightDim, 0.2, 0.9);
            dc.DrawGeometry(new SolidColorBrush(Color.FromArgb((byte)(opacity * 255), 0, 0, 0)), null, dim);
        }

        foreach (var a in doc.Annotations)
            if (!a.IsEffect && !ReferenceEquals(a, skip))
                a.Render(dc, ctx);
    }

    /// <summary>Flattens the document (crop applied) to a bitmap at full document resolution.</summary>
    public static BitmapSource RenderToBitmap(Document doc)
    {
        var view = doc.ViewRect;
        var dv = new DrawingVisual();
        using (var dc = dv.RenderOpen())
        {
            dc.PushClip(new RectangleGeometry(new Rect(0, 0, view.Width, view.Height)));
            dc.PushTransform(new TranslateTransform(-view.X, -view.Y));
            Draw(dc, doc, forExport: true);
            dc.Pop();
            dc.Pop();
        }
        var rtb = new RenderTargetBitmap(view.Width, view.Height, 96, 96, PixelFormats.Pbgra32);
        rtb.Render(dv);
        rtb.Freeze();
        return rtb;
    }
}
