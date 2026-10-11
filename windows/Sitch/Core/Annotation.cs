using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Sitch.Core;

public sealed class RenderContext
{
    public required BitmapSource Base { get; init; }
    public required int BaseVersion { get; init; }
    public bool ForExport { get; init; }
}

/// <summary>
/// One annotation object. The pristine capture is immutable; every mark — including the
/// obscure effects — is an object in the document's ordered list, editable until export.
/// All geometry is in document pixels.
/// </summary>
public abstract class Annotation
{
    public Color Color { get; set; } = (Color)ColorConverter.ConvertFromString("#FF3366");
    public double StrokeWidth { get; set; } = 6;

    /// <summary>Effects (obscure) render beneath the dim layer and all vector marks.</summary>
    public virtual bool IsEffect => false;
    public virtual bool IsSpotlight => false;

    public abstract Rect Bounds { get; }
    public abstract void Render(DrawingContext dc, RenderContext ctx);
    public abstract Annotation Clone();
    public abstract void MoveBy(Vector delta);

    /// <summary>Maps every point through <paramref name="map"/> (rotate/flip support).</summary>
    public abstract void ApplyTransform(Func<Point, Point> map);

    public virtual bool HitTest(Point p)
    {
        var b = Bounds;
        b.Inflate(5, 5);
        return b.Contains(p);
    }

    public virtual IReadOnlyList<Point> GetHandles() => Array.Empty<Point>();
    public virtual void MoveHandle(int index, Point p) { }

    protected static Point Mid(Point a, Point b) => new((a.X + b.X) / 2, (a.Y + b.Y) / 2);

    protected static double DistanceToSegment(Point p, Point a, Point b)
    {
        var ab = b - a;
        double len2 = ab.LengthSquared;
        if (len2 < 1e-6) return (p - a).Length;
        double t = Math.Clamp(Vector.Multiply(p - a, ab) / len2, 0, 1);
        return (p - (a + ab * t)).Length;
    }
}

/// <summary>Annotation defined by two free points (arrow, line).</summary>
public abstract class TwoPointAnnotation : Annotation
{
    public Point A { get; set; }
    public Point B { get; set; }

    public override Rect Bounds
    {
        get
        {
            var r = new Rect(A, B);
            r.Inflate(StrokeWidth * 1.6 + 4, StrokeWidth * 1.6 + 4);
            return r;
        }
    }

    public override void MoveBy(Vector delta) { A += delta; B += delta; }
    public override void ApplyTransform(Func<Point, Point> map) { A = map(A); B = map(B); }
    public override bool HitTest(Point p) => DistanceToSegment(p, A, B) <= Math.Max(7, StrokeWidth * 0.9);
    public override IReadOnlyList<Point> GetHandles() => [A, B];
    public override void MoveHandle(int index, Point p) { if (index == 0) A = p; else B = p; }
}

/// <summary>Annotation defined by an axis-aligned rectangle (shapes, obscure, spotlight, image…).</summary>
public abstract class RectAnnotation : Annotation
{
    public Point A { get; set; }
    public Point B { get; set; }

    public Rect Rect => new(A, B);

    public override Rect Bounds
    {
        get
        {
            var r = Rect;
            r.Inflate(StrokeWidth / 2 + 4, StrokeWidth / 2 + 4);
            return r;
        }
    }

    public override void MoveBy(Vector delta) { A += delta; B += delta; }
    public override void ApplyTransform(Func<Point, Point> map) { A = map(A); B = map(B); }
    public override bool HitTest(Point p)
    {
        var r = Rect;
        r.Inflate(5, 5);
        return r.Contains(p);
    }

    /// <summary>8 handles: 4 corners then 4 edge midpoints (order matters for MoveHandle).</summary>
    public override IReadOnlyList<Point> GetHandles()
    {
        var r = Rect;
        return
        [
            r.TopLeft, r.TopRight, r.BottomRight, r.BottomLeft,
            new(r.Left + r.Width / 2, r.Top), new(r.Right, r.Top + r.Height / 2),
            new(r.Left + r.Width / 2, r.Bottom), new(r.Left, r.Top + r.Height / 2),
        ];
    }

    public override void MoveHandle(int index, Point p)
    {
        var r = Rect;
        double left = r.Left, top = r.Top, right = r.Right, bottom = r.Bottom;
        switch (index)
        {
            case 0: left = p.X; top = p.Y; break;
            case 1: right = p.X; top = p.Y; break;
            case 2: right = p.X; bottom = p.Y; break;
            case 3: left = p.X; bottom = p.Y; break;
            case 4: top = p.Y; break;
            case 5: right = p.X; break;
            case 6: bottom = p.Y; break;
            case 7: left = p.X; break;
        }
        A = new Point(left, top);
        B = new Point(right, bottom);
    }
}
