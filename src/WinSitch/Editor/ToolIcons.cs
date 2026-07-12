using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Shapes;

namespace WinSitch.Editor;

public enum ToolKind
{
    Select, Arrow, Text, Rectangle, Ellipse, Line, Highlight,
    Obscure, Stamp, Pen, Spotlight, Sticker, Image, Crop,
}

/// <summary>Vector glyphs for the tool rail and option groups; brushes bind to the host's Foreground.</summary>
public static class ToolIcons
{
    public static FrameworkElement Create(ToolKind kind) => kind switch
    {
        ToolKind.Select => Fill("M5,2 L16,10.2 L10.6,11.3 L13.4,17.2 L11.1,18.3 L8.4,12.4 L5,15.6 Z"),
        ToolKind.Arrow => Fill("M3.6,14.6 L11.2,7 L9.6,5.3 L16,4 L14.7,10.4 L13,8.8 L5.4,16.4 Z"),
        ToolKind.Text => Text("Aa"),
        ToolKind.Rectangle => Stroke("M4.5,5.5 H15.5 V14.5 H4.5 Z"),
        ToolKind.Ellipse => Stroke("M10,4.5 A5.5,5 0 1 1 9.99,4.5 Z"),
        ToolKind.Line => Stroke("M4.5,15.5 L15.5,4.5"),
        ToolKind.Highlight => Fill("M6,11.5 L11.5,4.5 L15.5,7.5 L10.5,14 L6.8,14 Z M4,16.5 H16 V18 H4 Z"),
        ToolKind.Obscure => Fill("M4,4 H8 V8 H4 Z M12,4 H16 V8 H12 Z M8,8 H12 V12 H8 Z M4,12 H8 V16 H4 Z M12,12 H16 V16 H12 Z"),
        ToolKind.Stamp => StampGlyph(),
        ToolKind.Pen => Stroke("M3.5,15 C5.5,7 8,16.5 10.5,9 C12,5 14.5,7 16.5,5"),
        ToolKind.Spotlight => Stroke("M4,8 V4 H8 M12,4 H16 V8 M16,12 V16 H12 M8,16 H4 V12"),
        ToolKind.Sticker => Smiley(),
        ToolKind.Image => Stroke("M3.5,4.5 H16.5 V15.5 H3.5 Z M3.5,13 L8,9 L11.5,12 L13.5,10 L16.5,13 M12.8,7.2 A0.9,0.9 0 1 1 12.79,7.2"),
        ToolKind.Crop => Stroke("M6.5,2.5 V13.5 H17.5 M2.5,6.5 H13.5 V17.5"),
        _ => Stroke("M4,4 L16,16"),
    };

    public static readonly (ToolKind Kind, string Name)[] RailOrder =
    [
        (ToolKind.Select, "Select"), (ToolKind.Arrow, "Arrow"), (ToolKind.Text, "Text"),
        (ToolKind.Rectangle, "Rectangle"), (ToolKind.Ellipse, "Ellipse"), (ToolKind.Line, "Line"),
        (ToolKind.Highlight, "Highlight"), (ToolKind.Obscure, "Obscure"), (ToolKind.Stamp, "Stamp"),
        (ToolKind.Pen, "Pen"), (ToolKind.Spotlight, "Spotlight"), (ToolKind.Sticker, "Sticker"),
        (ToolKind.Image, "Image"), (ToolKind.Crop, "Crop"),
    ];

    // ---- Arrow style option glyphs ----------------------------------------------

    public static FrameworkElement ArrowStyleIcon(Core.ArrowStyle style) => style switch
    {
        Core.ArrowStyle.Tapered => Fill("M3,17 L11,8.4 L9.6,7 L16,4 L13,10.4 L11.6,9 L3.8,17.6 Z"),
        Core.ArrowStyle.Filled => Fill("M3,11.5 L10,11.5 L10,14.5 L17,10 L10,5.5 L10,8.5 L3,8.5 Z"),
        Core.ArrowStyle.Open => Stroke("M3,16 L16,4 M16,4 V10 M16,4 H10"),
        _ => Stroke("M4,11.5 L10,11.5 L10,14.5 L16.5,10 L10,5.5 L10,8.5 L4,8.5 Z"), // concave outline
    };

    public static FrameworkElement DoubleArrowIcon() =>
        Stroke("M3,10 H17 M6.5,6 L3,10 L6.5,14 M13.5,6 L17,10 L13.5,14");

    // ---- Builders -----------------------------------------------------------------

    private static Path Fill(string data)
    {
        var p = new Path
        {
            Data = Geometry.Parse(data),
            Width = 20, Height = 20,
            Stretch = Stretch.None,
        };
        Bind(p, Path.FillProperty);
        return p;
    }

    private static Path Stroke(string data, double thickness = 1.7)
    {
        var p = new Path
        {
            Data = Geometry.Parse(data),
            Width = 20, Height = 20,
            Stretch = Stretch.None,
            StrokeThickness = thickness,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
            StrokeLineJoin = PenLineJoin.Round,
        };
        Bind(p, Shape.StrokeProperty);
        return p;
    }

    private static TextBlock Text(string s)
    {
        var t = new TextBlock
        {
            Text = s,
            FontSize = 13,
            FontWeight = FontWeights.SemiBold,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        Bind(t, TextBlock.ForegroundProperty);
        return t;
    }

    private static FrameworkElement StampGlyph()
    {
        var grid = new Grid { Width = 20, Height = 20 };
        var circle = new Path
        {
            Data = Geometry.Parse("M10,3.5 A6.5,6.5 0 1 1 9.99,3.5 Z"),
            StrokeThickness = 1.7,
            Stretch = Stretch.None,
        };
        Bind(circle, Shape.StrokeProperty);
        var check = new Path
        {
            Data = Geometry.Parse("M7,10.2 L9.2,12.4 L13.4,7.8"),
            StrokeThickness = 1.7,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
            Stretch = Stretch.None,
        };
        Bind(check, Shape.StrokeProperty);
        grid.Children.Add(circle);
        grid.Children.Add(check);
        return grid;
    }

    private static FrameworkElement Smiley()
    {
        var grid = new Grid { Width = 20, Height = 20 };
        var face = new Path
        {
            Data = Geometry.Parse("M10,3.5 A6.5,6.5 0 1 1 9.99,3.5 Z M7.2,8.4 A0.4,0.4 0 1 1 7.19,8.4 M12.8,8.4 A0.4,0.4 0 1 1 12.79,8.4"),
            StrokeThickness = 1.7,
            Stretch = Stretch.None,
        };
        Bind(face, Shape.StrokeProperty);
        var smile = new Path
        {
            Data = Geometry.Parse("M6.8,11.5 Q10,14.5 13.2,11.5"),
            StrokeThickness = 1.7,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
            Stretch = Stretch.None,
        };
        Bind(smile, Shape.StrokeProperty);
        grid.Children.Add(face);
        grid.Children.Add(smile);
        return grid;
    }

    /// <summary>Binds a brush property to the nearest ContentControl ancestor's Foreground.</summary>
    private static void Bind(FrameworkElement el, DependencyProperty prop)
    {
        el.SetBinding(prop, new Binding("Foreground")
        {
            RelativeSource = new RelativeSource(RelativeSourceMode.FindAncestor, typeof(ContentControl), 1),
        });
    }
}
