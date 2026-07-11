using System.IO;
using System.Windows.Threading;

namespace WinSitch.Shell;

/// <summary>Opens the editor when Windows saves a system screenshot (Win+PrtScn → Pictures\Screenshots).</summary>
public sealed class ScreenshotWatcher : IDisposable
{
    private readonly FileSystemWatcher? _watcher;
    private readonly Action<string> _open;
    private readonly Dispatcher _dispatcher = Dispatcher.CurrentDispatcher;

    public ScreenshotWatcher(Action<string> open)
    {
        _open = open;
        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Screenshots");
        if (!Directory.Exists(dir)) return;
        _watcher = new FileSystemWatcher(dir, "*.png") { EnableRaisingEvents = true };
        _watcher.Created += OnCreated;
    }

    private void OnCreated(object sender, FileSystemEventArgs e)
    {
        // The file may still be locked while Windows writes it; retry briefly.
        _ = Task.Run(async () =>
        {
            for (int i = 0; i < 20; i++)
            {
                await Task.Delay(150);
                try
                {
                    using var fs = File.Open(e.FullPath, FileMode.Open, FileAccess.Read, FileShare.Read);
                    break;
                }
                catch (IOException) { }
            }
            _dispatcher.Invoke(() => _open(e.FullPath));
        });
    }

    public void Dispose()
    {
        if (_watcher is not null)
        {
            _watcher.EnableRaisingEvents = false;
            _watcher.Dispose();
        }
    }
}
