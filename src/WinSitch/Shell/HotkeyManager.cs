using System.Runtime.InteropServices;
using System.Windows.Interop;
using WinSitch.Core;

namespace WinSitch.Shell;

/// <summary>Global hotkeys via RegisterHotKey on a hidden message-only window.</summary>
public sealed class HotkeyManager : IDisposable
{
    private const int WmHotkey = 0x0312;
    private static readonly IntPtr HwndMessage = new(-3);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private readonly HwndSource _source;
    private readonly HashSet<int> _registered = new();

    public event Action<int>? Pressed;

    public HotkeyManager()
    {
        var p = new HwndSourceParameters("WinSitchHotkeys")
        {
            Width = 0, Height = 0, PositionX = 0, PositionY = 0,
            WindowStyle = 0,
            ParentWindow = HwndMessage,
        };
        _source = new HwndSource(p);
        _source.AddHook(WndProc);
    }

    public bool Register(int id, HotkeyChord chord)
    {
        Unregister(id);
        if (!RegisterHotKey(_source.Handle, id, chord.NativeModifiers, chord.VirtualKey))
            return false;
        _registered.Add(id);
        return true;
    }

    public void Unregister(int id)
    {
        if (_registered.Remove(id))
            UnregisterHotKey(_source.Handle, id);
    }

    public void UnregisterAll()
    {
        foreach (var id in _registered.ToList())
            Unregister(id);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmHotkey)
        {
            Pressed?.Invoke(wParam.ToInt32());
            handled = true;
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        UnregisterAll();
        _source.RemoveHook(WndProc);
        _source.Dispose();
    }
}
