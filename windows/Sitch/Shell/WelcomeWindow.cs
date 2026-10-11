using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Sitch.Shell;

/// <summary>
/// First-run welcome. Without it a fresh install is invisible: the app lives in the tray,
/// and Windows 11 hides new tray icons in the ^ overflow by default.
/// </summary>
public sealed class WelcomeWindow : Window
{
    public WelcomeWindow()
    {
        Title = "Welcome to Sitch";
        Width = 440;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Topmost = true;
        SetResourceReference(BackgroundProperty, "Brush.Window");
        SetResourceReference(ForegroundProperty, "Brush.Text");
        Icon = new BitmapImage(new Uri("pack://application:,,,/Assets/sitch.ico"));

        var panel = new StackPanel { Margin = new Thickness(28, 24, 28, 24) };

        var header = new StackPanel { Orientation = Orientation.Horizontal };
        header.Children.Add(new Image
        {
            Source = new BitmapImage(new Uri("pack://application:,,,/Assets/sitch.ico")),
            Width = 44, Height = 44, Margin = new Thickness(0, 0, 14, 0),
        });
        var titles = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        titles.Children.Add(new TextBlock
        { Text = "Sitch is ready", FontSize = 20, FontWeight = FontWeights.SemiBold });
        var sub = new TextBlock { Text = "Capture. Annotate. Share.", FontSize = 13 };
        sub.SetResourceReference(TextBlock.ForegroundProperty, "Brush.TextDim");
        titles.Children.Add(sub);
        header.Children.Add(titles);
        panel.Children.Add(header);

        panel.Children.Add(Line(
            $"Press  {App.Settings.CaptureHotkey}  to capture — drag a region or click a window.",
            topMargin: 20, bold: true));
        panel.Children.Add(Line(
            "Sitch lives in your system tray: click the pink-arrow icon to capture, " +
            "right-click it for window capture, full screen, timers and Settings."));
        panel.Children.Add(Line(
            "Tip: if you don't see the icon, it's in the  ^  overflow area next to the clock — " +
            "drag it onto the taskbar to pin it."));
        panel.Children.Add(Line(
            "Every capture is copied to your clipboard automatically, ready to paste."));

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 22, 0, 0),
        };
        var settings = new Button { Content = "Settings", Margin = new Thickness(0, 0, 8, 0) };
        settings.SetResourceReference(StyleProperty, "GhostButton");
        settings.Click += (_, _) => { App.Current.ShowSettings(); Close(); };
        var capture = new Button { Content = $"Capture now  ({App.Settings.CaptureHotkey})" };
        capture.SetResourceReference(StyleProperty, "PrimaryButton");
        capture.Click += (_, _) =>
        {
            Close();
            // Let the window vanish before the freeze-frame so it isn't in the shot.
            var t = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(180) };
            t.Tick += (_, _) => { t.Stop(); App.Current.CaptureRegion(); };
            t.Start();
        };
        buttons.Children.Add(settings);
        buttons.Children.Add(capture);
        panel.Children.Add(buttons);

        Content = panel;
    }

    private static TextBlock Line(string text, double topMargin = 12, bool bold = false)
    {
        return new TextBlock
        {
            Text = text,
            TextWrapping = TextWrapping.Wrap,
            FontSize = 13,
            FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal,
            Margin = new Thickness(0, topMargin, 0, 0),
            LineHeight = 19,
        };
    }
}
