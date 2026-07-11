using System.Windows;
using System.Windows.Media;

namespace WinSitch.Core;

/// <summary>Freehand stroke; also the base for the highlighter.</summary>
public class PenAnnotation : Annotation
{
    public List<Point> Points { get; set; } = new();

    protected virtual double EffectiveWidth => Math.Max(1.5, StrokeWidth * 0.45);
    protected virtual double StrokeOpacity => 1.0;

    public override Rect Bounds
    {
        get
        {
            if (Points.Count == 0) return Rect.Empty;
            double minX = Points.Min(p => p.X), maxX = Points.Max(p => p.X);
            double minY = Points.Min(p => p.Y), maxY = Points.Max(p => p.Y);
            var r = new Rect(new Point(minX, minY), new Point(maxX, maxY));
            r.Inflate(EffectiveWidth / 2 + 4, EffectiveWidth / 2 + 4);
            return r;
        }
    }

    public override void Render(DrawingContext dc, RenderContext ctx)
    {
        if (Points.Count < 2) return;
        var color = Color.FromArgb((byte)(255 * StrokeOpacity), Color.R, Color.G, Color.B);
        var pen = new Pen(new SolidColorBrush(color), EffectiveWidth)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round,
            LineJoin = PenLineJoin.Round,
        };
        var geo = new StreamGeometry();
        using (var g = geo.Open())
        {
            g.BeginFigure(Points[0], false, false);
            g.PolyLineTo(Points.Skip(1).ToList(), true, true);
        }
        geo.Freeze();
        dc.DrawGeometry(null, pen, geo);
    }

    public override bool HitTest(Point p)
    {
        double tol = Math.Max(7, EffectiveWidth * 0.7);
        for (int i = 1; i < Points.Count; i++)
            if (DistanceToSegment(p, Points[i - 1], Points[i]) <= tol) return true;
        return false;
    }

    public override void MoveBy(Vector delta)
    {
        for (int i = 0; i < Points.Count; i++) Points[i] += delta;
    }

    public override void ApplyTransform(Func<Point, Point> map)
    {
        for (int i = 0; i < Points.Count; i++) Points[i] = map(Points[i]);
    }

    public override Annotation Clone() => CloneInto(new PenAnnotation());

    protected Annotation CloneInto(PenAnnotation target)
    {
        target.Points = new List<Point>(Points);
        target.Color = Color;
        target.StrokeWidth = StrokeWidth;
        return target;
    }
}

/// <summary>Translucent marker wash — multiply-blend feel via opacity (default yellow).</summary>
public sealed class HighlightAnnotation : PenAnnotation
{
    protected override double EffectiveWidth => Math.Max(10, StrokeWidth);
    protected override double StrokeOpacity => 0.42;

    public override Annotation Clone() => CloneInto(new HighlightAnnotation());
}
