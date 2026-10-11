using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Sitch.Core;

public sealed class TextAnnotation : Annotation
{
    public Point Position { get; set; }      // top-left, doc px
    public string Text { get; set; } = "";
    public string FontFamily { get; set; } = "Segoe UI";
    public double FontSize { get; set; } = 28;
    public bool Bold { get; set; } = true;
    public bool Italic { get; set; }

    public override Rect Bounds
    {
        get
        {
            var ft = Format();
            return new Rect(Position, new Size(Math.Max(ft.WidthIncludingTrailingWhitespace, 8), Math.Max(ft.Height, 8)));
        }
    }

    private FormattedText Format() => new(
        Text.Length == 0 ? " " : Text,
        CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
        new Typeface(new FontFamily(FontFamily),
            Italic ? FontStyles.Italic : FontStyles.Normal,
            Bold ? FontWeights.Bold : FontWeights.Normal,
            FontStretches.Normal),
        FontSize, new SolidColorBrush(Color), 1.0);

    public override void Render(DrawingContext dc, RenderContext ctx)
    {
        if (Text.Length == 0) return;
        var ft = Format();
        // Subtle contrast halo so text stays readable on any background (Skitch-style).
        var halo = Format();
        halo.SetForegroundBrush(new SolidColorBrush(Color.FromArgb(0x59, 0, 0, 0)));
        dc.DrawText(halo, Position + new Vector(1.4, 1.4));
        dc.DrawText(ft, Position);
    }

    public override void MoveBy(Vector delta) => Position += delta;

    public override void ApplyTransform(Func<Point, Point> map)
    {
        // Text always renders rightward/downward from Position, so map the CENTER and
        // recenter — mapping the top-left directly would shift the label by its own
        // extent under flips/rotations.
        var b = Bounds;
        var c = map(new Point(b.X + b.Width / 2, b.Y + b.Height / 2));
        Position = new Point(c.X - b.Width / 2, c.Y - b.Height / 2);
    }

    public override Annotation Clone() => new TextAnnotation
    {
        Position = Position, Text = Text, FontFamily = FontFamily, FontSize = FontSize,
        Bold = Bold, Italic = Italic, Color = Color, StrokeWidth = StrokeWidth,
    };
}

public enum StampKind { Check, Cross, Star, Dot, Number }

/// <summary>Badge stamps: check / cross / star / dot, plus auto-incrementing numbers.</summary>
public sealed class StampAnnotation : Annotation
{
    public StampKind Kind { get; set; } = StampKind.Check;
    public int Number { get; set; } = 1;
    public Point Center { get; set; }
    public double Size { get; set; } = 46;

    public override Rect Bounds => new(Center.X - Size / 2, Center.Y - Size / 2, Size, Size);

    public override void Render(DrawingContext dc, RenderContext ctx)
    {
        double r = Size / 2;
        var badge = new SolidColorBrush(Color);
        dc.DrawEllipse(badge, null, Center, r, r);

        var white = Brushes.White;
        var pen = new Pen(white, Math.Max(2.5, Size * 0.09))
        { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
        double s = Size;

        switch (Kind)
        {
            case StampKind.Check:
                dc.DrawLine(pen, Center + new Vector(-s * 0.22, s * 0.02), Center + new Vector(-s * 0.06, s * 0.18));
                dc.DrawLine(pen, Center + new Vector(-s * 0.06, s * 0.18), Center + new Vector(s * 0.24, -s * 0.16));
                break;
            case StampKind.Cross:
                dc.DrawLine(pen, Center + new Vector(-s * 0.17, -s * 0.17), Center + new Vector(s * 0.17, s * 0.17));
                dc.DrawLine(pen, Center + new Vector(s * 0.17, -s * 0.17), Center + new Vector(-s * 0.17, s * 0.17));
                break;
            case StampKind.Star:
            {
                var geo = new StreamGeometry();
                using (var g = geo.Open())
                {
                    for (int i = 0; i < 10; i++)
                    {
                        double ang = -Math.PI / 2 + i * Math.PI / 5;
                        double rad = i % 2 == 0 ? s * 0.26 : s * 0.115;
                        var p = Center + new Vector(Math.Cos(ang) * rad, Math.Sin(ang) * rad);
                        if (i == 0) g.BeginFigure(p, true, true); else g.LineTo(p, false, false);
                    }
                }
                geo.Freeze();
                dc.DrawGeometry(white, null, geo);
                break;
            }
            case StampKind.Dot:
                dc.DrawEllipse(white, null, Center, s * 0.13, s * 0.13);
                break;
            case StampKind.Number:
            {
                var ft = new FormattedText(Number.ToString(), CultureInfo.InvariantCulture,
                    FlowDirection.LeftToRight,
                    new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal),
                    Size * (Number < 10 ? 0.52 : 0.42), white, 1.0);
                dc.DrawText(ft, new Point(Center.X - ft.WidthIncludingTrailingWhitespace / 2, Center.Y - ft.Height / 2));
                break;
            }
        }
    }

    public override void MoveBy(Vector delta) => Center += delta;
    public override void ApplyTransform(Func<Point, Point> map) => Center = map(Center);

    // Handle sits ON the badge circle (distance Size/2 from center), so the inverse is dist*2.
    public override IReadOnlyList<Point> GetHandles() =>
        [new(Center.X + Size / 2 * 0.7071, Center.Y + Size / 2 * 0.7071)];

    public override void MoveHandle(int index, Point p) =>
        Size = Math.Clamp((p - Center).Length * 2, 18, 400);

    public override Annotation Clone() => new StampAnnotation
    { Kind = Kind, Number = Number, Center = Center, Size = Size, Color = Color, StrokeWidth = StrokeWidth };
}

/// <summary>Emoji sticker (rendered with Segoe UI Emoji).</summary>
public sealed class StickerAnnotation : Annotation
{
    public string Emoji { get; set; } = "😀";
    public Point Center { get; set; }
    public double Size { get; set; } = 72;

    public override Rect Bounds => new(Center.X - Size / 2, Center.Y - Size / 2, Size, Size);

    public override void Render(DrawingContext dc, RenderContext ctx)
    {
        var ft = new FormattedText(Emoji, CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
            new Typeface("Segoe UI Emoji"), Size * 0.8, Brushes.Black, 1.0);
        dc.DrawText(ft, new Point(Center.X - ft.WidthIncludingTrailingWhitespace / 2, Center.Y - ft.Height / 2));
    }

    public override void MoveBy(Vector delta) => Center += delta;
    public override void ApplyTransform(Func<Point, Point> map) => Center = map(Center);

    public override IReadOnlyList<Point> GetHandles() =>
        [new(Center.X + Size / 2 * 0.7071, Center.Y + Size / 2 * 0.7071)];

    public override void MoveHandle(int index, Point p) =>
        Size = Math.Clamp((p - Center).Length * 2, 20, 600);

    public override Annotation Clone() => new StickerAnnotation
    { Emoji = Emoji, Center = Center, Size = Size, Color = Color, StrokeWidth = StrokeWidth };
}

/// <summary>Image-over-image overlay.</summary>
public sealed class ImageAnnotation : RectAnnotation
{
    public BitmapSource? Source { get; set; }

    public override void Render(DrawingContext dc, RenderContext ctx)
    {
        if (Source is null) return;
        var r = Rect;
        if (r.Width < 1 || r.Height < 1) return;
        dc.DrawImage(Source, r);
    }

    public override Annotation Clone() => new ImageAnnotation
    { A = A, B = B, Source = Source, Color = Color, StrokeWidth = StrokeWidth };
}
