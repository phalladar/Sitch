using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using WinSitch.Core;
using WinSitch.Shell;

namespace WinSitch.Editor;

/// <summary>
/// `--demo` CLI mode: opens the editor on a synthetic dashboard capture with annotations
/// pre-placed. Used for README screenshots and quick smoke tests — no capture required.
/// </summary>
public static class DemoMode
{
    public static void OpenEditorDemo(bool cropMode = false, bool lightTheme = false)
    {
        if (lightTheme) ThemeManager.Apply("Light");

        var bmp = RenderMockDashboard();
        var win = new EditorWindow(bmp, "Q3 Dashboard");
        win.Show();
        win.Activate();
        win.Dispatcher.BeginInvoke(() => win.SetUpDemoAnnotations(cropMode),
            System.Windows.Threading.DispatcherPriority.Loaded);
    }

    /// <summary>
    /// Renders the region-capture overlay illustration against the demo dashboard
    /// (same dim/marquee/readout visuals as the live overlay) and writes it to a PNG.
    /// Used to produce a privacy-safe README asset.
    /// </summary>
    public static void RenderRegionShot(string path)
    {
        var bmp = RenderMockDashboard();
        int w = bmp.PixelWidth, h = bmp.PixelHeight;
        var sel = new Rect(320, 170, 760, 560);

        var dv = new DrawingVisual();
        using (var dc = dv.RenderOpen())
        {
            dc.DrawImage(bmp, new Rect(0, 0, w, h));
            var dim = new CombinedGeometry(GeometryCombineMode.Exclude,
                new RectangleGeometry(new Rect(0, 0, w, h)), new RectangleGeometry(sel));
            dc.DrawGeometry(new SolidColorBrush(Color.FromArgb(0x73, 0, 0, 0)), null, dim);
            dc.DrawRectangle(null, new Pen(new SolidColorBrush(Color.FromRgb(0xFF, 0x33, 0x66)), 2), sel);

            var ft = new FormattedText($"{(int)sel.Width} × {(int)sel.Height}",
                CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
                new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal),
                20, Brushes.White, 1.0);
            var bg = new Rect(sel.Right + 12, sel.Bottom + 12, ft.Width + 16, ft.Height + 12);
            dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(0xD9, 0x1E, 0x1E, 0x20)), null, bg, 6, 6);
            dc.DrawText(ft, new Point(bg.X + 8, bg.Y + 6));
        }
        var rtb = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32);
        rtb.Render(dv);
        Export.Exporters.Save(rtb, path);
    }

    /// <summary>A fake marketing dashboard, in the spirit of the classic annotation-app demo shot.</summary>
    private static BitmapSource RenderMockDashboard()
    {
        const int W = 1500, H = 950;
        var dv = new DrawingVisual();
        using (var dc = dv.RenderOpen())
        {
            var bg = new LinearGradientBrush(Color.FromRgb(0xF2, 0xF3, 0xF7), Color.FromRgb(0xE8, 0xEA, 0xF0), 90);
            dc.DrawRectangle(bg, null, new Rect(0, 0, W, H));

            // Browser chrome
            dc.DrawRoundedRectangle(Brushes.White, null, new Rect(40, 30, W - 80, H - 70), 10, 10);
            dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(0xEE, 0xEF, 0xF3)), null, new Rect(40, 30, W - 80, 46));
            foreach (var (x, c) in new[] { (64, "#FF5F57"), (86, "#FEBC2E"), (108, "#28C840") })
                dc.DrawEllipse(new SolidColorBrush((Color)ColorConverter.ConvertFromString(c)), null, new Point(x, 53), 7, 7);
            dc.DrawRoundedRectangle(Brushes.White, null, new Rect(140, 40, W - 260, 26), 13, 13);
            Text(dc, "app.example.com/marketing/q3", 158, 45, 13, "#9A9AA2");

            Text(dc, "Q3 — Marketing Performance Dashboard", 90, 110, 30, "#1D1D28", bold: true);
            Text(dc, "Period: Jul 1 — Sep 30   ·   Updated 2 min ago", 92, 152, 14, "#8A8A94");

            // KPI cards
            (string Label, string Value, string Delta, string DeltaColor)[] cards =
            [
                ("Total Revenue", "$284,920", "+12.4%", "#28A745"),
                ("New Customers", "1,847", "+8.1%", "#28A745"),
                ("Conversion Rate", "4.8%", "+0.6%", "#28A745"),
                ("Churn", "2.1%", "−0.3%", "#D9534F"),
            ];
            for (int i = 0; i < cards.Length; i++)
            {
                double x = 90 + i * 335;
                var r = new Rect(x, 195, 305, 130);
                dc.DrawRoundedRectangle(Brushes.White, new Pen(new SolidColorBrush(Color.FromRgb(0xE3, 0xE4, 0xEA)), 1), r, 10, 10);
                Text(dc, cards[i].Label, x + 22, 215, 13, "#8A8A94");
                Text(dc, cards[i].Value, x + 22, 240, 30, "#1D1D28", bold: true);
                Text(dc, cards[i].Delta, x + 22, 288, 14, cards[i].DeltaColor, bold: true);
            }

            // Table
            var table = new Rect(90, 370, 1320, 480);
            dc.DrawRoundedRectangle(Brushes.White, new Pen(new SolidColorBrush(Color.FromRgb(0xE3, 0xE4, 0xEA)), 1), table, 10, 10);
            string[] headers = ["Product", "Region", "Sessions", "Conv. rate", "Revenue"];
            double[] cols = [120, 470, 760, 990, 1220];
            for (int i = 0; i < headers.Length; i++)
                Text(dc, headers[i], cols[i], 395, 13, "#8A8A94", bold: true);
            dc.DrawLine(new Pen(new SolidColorBrush(Color.FromRgb(0xE9, 0xEA, 0xEF)), 1),
                new Point(105, 428), new Point(1395, 428));

            (string P, string R, string S, string C, string V)[] rows =
            [
                ("Aurora Suite", "Worldwide", "12,840", "5.4%", "$48,210"),
                ("Pencil for Tablet", "EU", "8,221", "4.2%", "$32,180"),
                ("Pixel Garage", "US", "21,003", "3.1%", "$28,940"),
                ("Pencil for Desktop", "EU", "6,540", "3.8%", "$19,260"),
                ("Workshop Pro", "LATAM", "4,109", "2.9%", "$11,840"),
                ("Vivo Hosting", "Spain", "3,820", "2.4%", "$9,420"),
                ("Beacon Analytics", "APAC", "2,977", "2.2%", "$7,730"),
            ];
            for (int i = 0; i < rows.Length; i++)
            {
                double y = 450 + i * 55;
                if (i % 2 == 1)
                    dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(0xFA, 0xFA, 0xFC)), null,
                        new Rect(105, y - 12, 1290, 46));
                Text(dc, rows[i].P, cols[0], y, 15, "#2B2B33");
                Text(dc, rows[i].R, cols[1], y, 15, "#6E6E78");
                Text(dc, rows[i].S, cols[2], y, 15, "#2B2B33");
                Text(dc, rows[i].C, cols[3], y, 15, "#2B2B33");
                Text(dc, rows[i].V, cols[4], y, 15, "#2B2B33", bold: true);
            }
        }
        var rtb = new RenderTargetBitmap(W, H, 96, 96, PixelFormats.Pbgra32);
        rtb.Render(dv);
        rtb.Freeze();
        return rtb;
    }

    private static void Text(DrawingContext dc, string text, double x, double y, double size,
        string color, bool bold = false)
    {
        var ft = new FormattedText(text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
            new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal,
                bold ? FontWeights.SemiBold : FontWeights.Normal, FontStretches.Normal),
            size, new SolidColorBrush((Color)ColorConverter.ConvertFromString(color)), 1.0);
        dc.DrawText(ft, new Point(x, y));
    }
}
