using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Sitch.Core;

public enum ObscureStyle { Pixelate, Blur, Block, Stripes }

/// <summary>
/// Redaction effect object. Non-destructive: samples the pristine base image each time the
/// covered region changes and is only baked into pixels at export. Pixelate/blur always
/// compute from the full-resolution source; block/stripes are opaque ink — the safe choice
/// for real secrets.
/// </summary>
public sealed class ObscureAnnotation : RectAnnotation
{
    public ObscureStyle Style { get; set; } = ObscureStyle.Pixelate;

    private BitmapSource? _cache;
    private (Int32Rect Rect, ObscureStyle Style, int BaseVersion) _cacheKey;

    public override bool IsEffect => true;

    public override void Render(DrawingContext dc, RenderContext ctx)
    {
        var r = Rect;
        if (r.Width < 2 || r.Height < 2) return;

        var clipped = Intersect(r, new Rect(0, 0, ctx.Base.PixelWidth, ctx.Base.PixelHeight));
        if (clipped.Width < 2 || clipped.Height < 2) return;
        var ir = new Int32Rect((int)clipped.X, (int)clipped.Y,
            Math.Max(1, (int)Math.Round(clipped.Width)), Math.Max(1, (int)Math.Round(clipped.Height)));
        ir.Width = Math.Min(ir.Width, ctx.Base.PixelWidth - ir.X);
        ir.Height = Math.Min(ir.Height, ctx.Base.PixelHeight - ir.Y);
        if (ir.Width < 2 || ir.Height < 2) return;

        switch (Style)
        {
            case ObscureStyle.Block:
                dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(0x1D, 0x1D, 0x1F)), null,
                    new Rect(ir.X, ir.Y, ir.Width, ir.Height));
                return;

            case ObscureStyle.Stripes:
            {
                var rect = new Rect(ir.X, ir.Y, ir.Width, ir.Height);
                dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(0x1D, 0x1D, 0x1F)), null, rect);
                dc.PushClip(new RectangleGeometry(rect));
                var stripePen = new Pen(new SolidColorBrush(Color.FromRgb(0x3C, 0x3C, 0x40)), 7);
                double span = ir.Width + ir.Height;
                for (double o = 0; o < span; o += 18)
                    dc.DrawLine(stripePen, new Point(ir.X + o, ir.Y - 4), new Point(ir.X + o - ir.Height - 8, ir.Y + ir.Height + 4));
                dc.Pop();
                return;
            }
        }

        // Pixelate / blur: cached full-res sample of the pristine base.
        var key = (ir, Style, ctx.BaseVersion);
        if (_cache is null || !_cacheKey.Equals(key))
        {
            _cache = Style == ObscureStyle.Pixelate
                ? EffectRenderer.Pixelate(ctx.Base, ir)
                : EffectRenderer.BoxBlur(ctx.Base, ir, radius: 12);
            _cacheKey = key;
        }
        dc.DrawImage(_cache, new Rect(ir.X, ir.Y, ir.Width, ir.Height));
    }

    private static Rect Intersect(Rect a, Rect b)
    {
        a.Intersect(b);
        return a.IsEmpty ? new Rect(0, 0, 0, 0) : a;
    }

    public override Annotation Clone() => new ObscureAnnotation
    { A = A, B = B, Style = Style, Color = Color, StrokeWidth = StrokeWidth };
}

/// <summary>
/// Spotlight region: the renderer dims everything except the union of all spotlight rects.
/// Multiple spotlights are supported; the object itself draws nothing.
/// </summary>
public sealed class SpotlightAnnotation : RectAnnotation
{
    public override bool IsEffect => true;
    public override bool IsSpotlight => true;

    public override void Render(DrawingContext dc, RenderContext ctx) { /* composed by Renderer */ }

    public override Annotation Clone() => new SpotlightAnnotation
    { A = A, B = B, Color = Color, StrokeWidth = StrokeWidth };
}

/// <summary>Pixel operations for the obscure effects. Always fed by the full-res pristine base.</summary>
public static class EffectRenderer
{
    public static BitmapSource Pixelate(BitmapSource source, Int32Rect region)
    {
        var (pixels, w, h, stride) = ReadRegion(source, region);
        // Mosaic strength scales with region size; floor keeps small regions genuinely unreadable.
        int block = Math.Clamp(Math.Min(w, h) / 12, 10, 56);

        for (int by = 0; by < h; by += block)
        for (int bx = 0; bx < w; bx += block)
        {
            int bw = Math.Min(block, w - bx), bh = Math.Min(block, h - by);
            long b = 0, g = 0, r = 0;
            for (int y = by; y < by + bh; y++)
            {
                int row = y * stride + bx * 4;
                for (int x = 0; x < bw; x++)
                {
                    b += pixels[row]; g += pixels[row + 1]; r += pixels[row + 2];
                    row += 4;
                }
            }
            int n = bw * bh;
            byte ab = (byte)(b / n), ag = (byte)(g / n), ar = (byte)(r / n);
            for (int y = by; y < by + bh; y++)
            {
                int row = y * stride + bx * 4;
                for (int x = 0; x < bw; x++)
                {
                    pixels[row] = ab; pixels[row + 1] = ag; pixels[row + 2] = ar; pixels[row + 3] = 255;
                    row += 4;
                }
            }
        }
        return Write(pixels, w, h, stride);
    }

    public static BitmapSource BoxBlur(BitmapSource source, Int32Rect region, int radius)
    {
        var (pixels, w, h, stride) = ReadRegion(source, region);
        var tmp = new byte[pixels.Length];
        // Two box passes ≈ triangular kernel; enough smoothing for redaction preview.
        BlurPass(pixels, tmp, w, h, stride, radius, horizontal: true);
        BlurPass(tmp, pixels, w, h, stride, radius, horizontal: false);
        BlurPass(pixels, tmp, w, h, stride, radius, horizontal: true);
        BlurPass(tmp, pixels, w, h, stride, radius, horizontal: false);
        return Write(pixels, w, h, stride);
    }

    private static void BlurPass(byte[] src, byte[] dst, int w, int h, int stride, int radius, bool horizontal)
    {
        int outer = horizontal ? h : w;
        int inner = horizontal ? w : h;
        for (int o = 0; o < outer; o++)
        {
            long sb = 0, sg = 0, sr = 0;
            int count = 0;
            int Idx(int i) => horizontal ? o * stride + i * 4 : i * stride + o * 4;

            int rEnd = Math.Min(radius, inner - 1);
            for (int i = 0; i <= rEnd; i++)
            {
                int idx = Idx(i);
                sb += src[idx]; sg += src[idx + 1]; sr += src[idx + 2];
                count++;
            }
            for (int i = 0; i < inner; i++)
            {
                int add = i + radius + 1, remove = i - radius;
                if (add < inner)
                {
                    int idx = Idx(add);
                    sb += src[idx]; sg += src[idx + 1]; sr += src[idx + 2];
                    count++;
                }
                if (remove >= 0)
                {
                    int idx = Idx(remove);
                    sb -= src[idx]; sg -= src[idx + 1]; sr -= src[idx + 2];
                    count--;
                }
                int di = Idx(i);
                dst[di] = (byte)(sb / count);
                dst[di + 1] = (byte)(sg / count);
                dst[di + 2] = (byte)(sr / count);
                dst[di + 3] = 255;
            }
        }
    }

    private static (byte[] Pixels, int W, int H, int Stride) ReadRegion(BitmapSource source, Int32Rect region)
    {
        var src = source.Format == PixelFormats.Bgra32 || source.Format == PixelFormats.Bgr32
            ? source
            : new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        int stride = region.Width * 4;
        var pixels = new byte[stride * region.Height];
        src.CopyPixels(region, pixels, stride, 0);
        return (pixels, region.Width, region.Height, stride);
    }

    private static BitmapSource Write(byte[] pixels, int w, int h, int stride)
    {
        var bmp = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, pixels, stride);
        bmp.Freeze();
        return bmp;
    }
}
