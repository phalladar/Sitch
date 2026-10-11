using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace Sitch.Shell;

/// <summary>Capture-timer countdown (3/5/10 s) shown center-screen, then runs the capture.</summary>
public static class CountdownPopup
{
    public static void Run(int seconds, Action onDone)
    {
        var label = new TextBlock
        {
            Text = seconds.ToString(),
            FontSize = 64,
            FontWeight = FontWeights.Bold,
            Foreground = Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        var win = new Window
        {
            WindowStyle = WindowStyle.None,
            ResizeMode = ResizeMode.NoResize,
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            ShowInTaskbar = false,
            ShowActivated = false,
            Topmost = true,
            Width = 140, Height = 140,
            WindowStartupLocation = WindowStartupLocation.CenterScreen,
            Content = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(0xD8, 0x1E, 0x1E, 0x20)),
                CornerRadius = new CornerRadius(24),
                Child = label,
            },
        };
        win.Show();

        int remaining = seconds;
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        timer.Tick += (_, _) =>
        {
            remaining--;
            if (remaining <= 0)
            {
                timer.Stop();
                win.Close();
                // Give the countdown window a beat to vanish before the freeze-frame.
                var d = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(120) };
                d.Tick += (_, _) => { d.Stop(); onDone(); };
                d.Start();
            }
            else label.Text = remaining.ToString();
        };
        timer.Start();
    }
}
