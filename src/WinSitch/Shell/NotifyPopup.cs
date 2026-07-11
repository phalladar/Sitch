using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace WinSitch.Shell;

/// <summary>Small self-drawn toast in the bottom-right corner (no COM toast registration needed).</summary>
public static class NotifyPopup
{
    public static void Show(string text, BitmapSource? thumbnail = null)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal };
        if (thumbnail is not null)
        {
            panel.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(4),
                Margin = new Thickness(0, 0, 10, 0),
                MaxWidth = 72, MaxHeight = 48,
                Child = new Image { Source = thumbnail, Stretch = Stretch.Uniform },
            });
        }
        panel.Children.Add(new TextBlock
        {
            Text = text,
            Foreground = Brushes.White,
            VerticalAlignment = VerticalAlignment.Center,
            FontSize = 13,
            MaxWidth = 260,
            TextWrapping = TextWrapping.Wrap,
        });

        var win = new Window
        {
            WindowStyle = WindowStyle.None,
            ResizeMode = ResizeMode.NoResize,
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            ShowInTaskbar = false,
            ShowActivated = false,
            Topmost = true,
            SizeToContent = SizeToContent.WidthAndHeight,
            Content = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(0xF2, 0x28, 0x28, 0x2A)),
                CornerRadius = new CornerRadius(10),
                Padding = new Thickness(14, 10, 14, 10),
                Child = panel,
            },
        };

        win.Loaded += (_, _) =>
        {
            var wa = SystemParameters.WorkArea;
            win.Left = wa.Right - win.ActualWidth - 16;
            win.Top = wa.Bottom - win.ActualHeight - 16;
        };
        win.Show();

        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(2200) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            var fade = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(300));
            fade.Completed += (_, _) => win.Close();
            win.BeginAnimation(UIElement.OpacityProperty, fade);
        };
        timer.Start();
    }
}
