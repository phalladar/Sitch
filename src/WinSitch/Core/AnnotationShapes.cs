using System.Windows;
using System.Windows.Media;

namespace WinSitch.Core;

public enum ArrowStyle { Tapered, Filled, Open, Concave }

/// <summary>The iconic Skitch-style arrow. A = tail, B = tip.</summary>
public sealed class ArrowAnnotation : TwoPointAnnotation
{
    public ArrowStyle Style { get; set; } = ArrowStyle.Tapered;
    public bool DoubleHeaded { get; set; }

    public override void Render(DrawingContext dc, RenderContext ctx)
    {
        var v = B - A;
        double len = v.Length;
        if (len < 2) return;
        var dir = v / len;
        var perp = new Vector(-dir.Y, dir.X);
        double w = Math.Max(2, StrokeWidth);
        var brush = new SolidColorBrush(Color);

        // Head scales with arrow length (a short arrow keeps a proportionate head),
        // bounded by the stroke width so extremes stay sane.
        double headLen = Math.Clamp(len * (DoubleHeaded ? 0.24 : 0.30), Math.Max(10, w * 1.1), w * 3.4);
        double headHalf = headLen * 0.42;

        switch (Style)
        {
            case ArrowStyle.Tapered:
                dc.DrawGeometry(brush, null, TaperedGeometry(A, B, dir, perp, w, headLen, headHalf, DoubleHeaded));
                break;

            case ArrowStyle.Filled:
            {
                double shaft = w * 0.42;
                var geo = new StreamGeometry();
                using (var g = geo.Open())
                {
                    Point tail = DoubleHeaded ? A + dir * headLen : A;
                    Point headBase = B - dir * headLen;
                    g.BeginFigure(tail + perp * shaft, isFilled: true, isClosed: true);
                    g.LineTo(headBase + perp * shaft, false, false);
                    g.LineTo(headBase + perp * headHalf, false, false);
                    g.LineTo(B, false, false);
                    g.LineTo(headBase - perp * headHalf, false, false);
                    g.LineTo(headBase - perp * shaft, false, false);
                    g.LineTo(tail - perp * shaft, false, false);
                    if (DoubleHeaded)
                    {
                        g.LineTo(A + dir * headLen - perp * headHalf, false, false);
                        g.LineTo(A, false, false);
                        g.LineTo(A + dir * headLen + perp * headHalf, false, false);
                    }
                }
                geo.Freeze();
                dc.DrawGeometry(brush, null, geo);
                break;
            }

            case ArrowStyle.Open:
            {
                var pen = new Pen(brush, Math.Max(2, w * 0.45)) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
                dc.DrawLine(pen, A, B);
                DrawOpenHead(dc, pen, B, dir, perp, headLen, headHalf * 1.2);
                if (DoubleHeaded) DrawOpenHead(dc, pen, A, -dir, perp, headLen, headHalf * 1.2);
                break;
            }

            case ArrowStyle.Concave:
            {
                // Block arrow whose tail edge is notched inward (⇨ feel).
                double shaft = w * 0.55;
                Point tail = DoubleHeaded ? A + dir * headLen : A;
                Point headBase = B - dir * headLen;
                var geo = new StreamGeometry();
                using (var g = geo.Open())
                {
                    g.BeginFigure(tail + perp * shaft, true, true);
                    g.LineTo(headBase + perp * shaft, false, false);
                    g.LineTo(headBase + perp * headHalf, false, false);
                    g.LineTo(B, false, false);
                    g.LineTo(headBase - perp * headHalf, false, false);
                    g.LineTo(headBase - perp * shaft, false, false);
                    g.LineTo(tail - perp * shaft, false, false);
                    if (DoubleHeaded)
                    {
                        g.LineTo(A + dir * headLen - perp * headHalf, false, false);
                        g.LineTo(A, false, false);
                        g.LineTo(A + dir * headLen + perp * headHalf, false, false);
                    }
                    else
                    {
                        g.LineTo(A + dir * (shaft * 1.2), false, false); // concave notch
                    }
                }
                geo.Freeze();
                var pen = new Pen(brush, Math.Max(2, w * 0.28)) { LineJoin = PenLineJoin.Round };
                dc.DrawGeometry(null, pen, geo);
                break;
            }
        }
    }

    /// <summary>
    /// The signature Skitch taper: widest at the tail, concave flanks sweeping to a thin
    /// neck, then a sleek head with slightly swept-back barbs.
    /// </summary>
    private static Geometry TaperedGeometry(Point a, Point b, Vector dir, Vector perp,
        double w, double headLen, double headHalf, bool doubleHeaded)
    {
        double tailHalf = w * 0.5;
        double neck = Math.Max(1.4, w * 0.17);
        Point headBase = b - dir * headLen;
        Point barbBack = headBase - dir * (headLen * 0.10); // barbs sweep a touch behind the base

        var geo = new StreamGeometry();
        using (var g = geo.Open())
        {
            if (doubleHeaded)
            {
                // Mirrored heads with a gentle belly between the two necks.
                Point tailBase = a + dir * headLen;
                Point tailBarb = tailBase + dir * (headLen * 0.10);
                Point mid = tailBase + (headBase - tailBase) * 0.5;
                double belly = Math.Max(neck * 1.6, tailHalf * 0.5);

                g.BeginFigure(tailBase + perp * neck, true, true);
                g.QuadraticBezierTo(mid + perp * belly, headBase + perp * neck, false, false);
                g.LineTo(barbBack + perp * headHalf, false, false);
                g.LineTo(b, false, false);
                g.LineTo(barbBack - perp * headHalf, false, false);
                g.LineTo(headBase - perp * neck, false, false);
                g.QuadraticBezierTo(mid - perp * belly, tailBase - perp * neck, false, false);
                g.LineTo(tailBarb - perp * headHalf, false, false);
                g.LineTo(a, false, false);
                g.LineTo(tailBarb + perp * headHalf, false, false);
            }
            else
            {
                // Concave flanks: the control point sits close to the spine so the
                // silhouette sweeps inward instead of ballooning.
                Point ctrlBase = a + (headBase - a) * 0.58;
                double ctrlOff = neck + (tailHalf - neck) * 0.22;

                g.BeginFigure(a + perp * tailHalf, true, true);
                g.QuadraticBezierTo(ctrlBase + perp * ctrlOff, headBase + perp * neck, false, false);
                g.LineTo(barbBack + perp * headHalf, false, false);
                g.LineTo(b, false, false);
                g.LineTo(barbBack - perp * headHalf, false, false);
                g.LineTo(headBase - perp * neck, false, false);
                g.QuadraticBezierTo(ctrlBase - perp * ctrlOff, a - perp * tailHalf, false, false);
            }
        }
        geo.Freeze();
        return geo;
    }

    private static void DrawOpenHead(DrawingContext dc, Pen pen, Point tip, Vector dir, Vector perp,
        double headLen, double headHalf)
    {
        var back = tip - dir * headLen;
        dc.DrawLine(pen, tip, back + perp * headHalf);
        dc.DrawLine(pen, tip, back - perp * headHalf);
    }

    public override Annotation Clone() => new ArrowAnnotation
    {
        A = A, B = B, Color = Color, StrokeWidth = StrokeWidth, Style = Style, DoubleHeaded = DoubleHeaded,
    };
}

public sealed class LineAnnotation : TwoPointAnnotation
{
    public override void Render(DrawingContext dc, RenderContext ctx)
    {
        var pen = new Pen(new SolidColorBrush(Color), Math.Max(1, StrokeWidth * 0.45))
        { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        dc.DrawLine(pen, A, B);
    }

    public override Annotation Clone() => new LineAnnotation { A = A, B = B, Color = Color, StrokeWidth = StrokeWidth };
}

public sealed class BoxAnnotation : RectAnnotation
{
    /// <summary>true = ellipse, false = rectangle.</summary>
    public bool IsEllipse { get; set; }
    public bool Filled { get; set; }

    public override void Render(DrawingContext dc, RenderContext ctx)
    {
        var r = Rect;
        if (r.Width < 1 || r.Height < 1) return;
        var brush = new SolidColorBrush(Color);
        var pen = Filled ? null : new Pen(brush, Math.Max(1, StrokeWidth * 0.45)) { LineJoin = PenLineJoin.Round };
        var fill = Filled ? brush : null;
        if (IsEllipse)
            dc.DrawEllipse(fill, pen, new Point(r.X + r.Width / 2, r.Y + r.Height / 2), r.Width / 2, r.Height / 2);
        else
            dc.DrawRoundedRectangle(fill, pen, r, 2, 2);
    }

    public override bool HitTest(Point p)
    {
        var r = Rect;
        if (Filled)
        {
            r.Inflate(5, 5);
            return r.Contains(p);
        }
        var outer = r; outer.Inflate(Math.Max(6, StrokeWidth * 0.5), Math.Max(6, StrokeWidth * 0.5));
        var inner = r; inner.Inflate(-Math.Max(6, StrokeWidth * 0.5), -Math.Max(6, StrokeWidth * 0.5));
        if (IsEllipse)
        {
            // Cheap ellipse ring test via normalized radius.
            if (r.Width < 2 || r.Height < 2) return outer.Contains(p);
            double nx = (p.X - (r.X + r.Width / 2)) / (r.Width / 2);
            double ny = (p.Y - (r.Y + r.Height / 2)) / (r.Height / 2);
            double d = nx * nx + ny * ny;
            double tol = Math.Max(0.18, StrokeWidth / Math.Min(r.Width, r.Height) * 2.4);
            return Math.Abs(Math.Sqrt(d) - 1) < tol;
        }
        return outer.Contains(p) && (!inner.Contains(p) || inner.Width <= 0 || inner.Height <= 0);
    }

    public override Annotation Clone() => new BoxAnnotation
    { A = A, B = B, Color = Color, StrokeWidth = StrokeWidth, IsEllipse = IsEllipse, Filled = Filled };
}
