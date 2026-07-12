using System.Windows;
using System.Windows.Media.Imaging;
using WinSitch.Core;

namespace WinSitch.Capture;

public enum CaptureMode { Region, Window, FullScreen }

/// <param name="PhysicalRect">Region rect for recapture-last (regions only).</param>
/// <param name="SourceScreenRect">Where on screen the capture came from (all modes) — used to open the editor on that display.</param>
public sealed record CaptureResult(BitmapSource Bitmap, CaptureMode Kind,
    PixelRect? PhysicalRect, PixelRect? SourceScreenRect);

/// <summary>
/// Orchestrates interactive capture: freezes the desktop once, opens one overlay window per
/// monitor (each at that monitor's DPI), and completes with a crop of the frozen frame.
/// All selection state lives here, in physical virtual-screen coordinates, so a drag can
/// span monitors with different scale factors. In Region mode a plain click (no drag)
/// captures the hovered window — one hotkey covers region AND window, Skitch-style.
/// Arrow keys define/nudge a selection, Enter confirms (keyboard capture).
/// </summary>
public sealed class CaptureController
{
    private readonly List<OverlayWindow> _overlays = new();
    private Action<CaptureResult>? _onDone;
    private BitmapSource? _frozen;
    private Int32Rect _frozenBounds;
    private CaptureMode _mode;
    private List<WindowEntry>? _windows;
    public bool IsActive { get; private set; }

    // Selection state (physical px, virtual-screen space)
    public bool Dragging { get; private set; }
    public bool HasKeyboardSelection { get; private set; }
    public Point DragStart { get; private set; }
    public Point DragCurrent { get; private set; }
    public Point PointerPhysical { get; private set; }
    public WindowEntry? HoveredWindow { get; private set; }
    public CaptureMode Mode => _mode;

    public bool HasSelection => Dragging || HasKeyboardSelection;

    public Int32Rect SelectionRect
    {
        get
        {
            int x1 = (int)Math.Round(Math.Min(DragStart.X, DragCurrent.X));
            int y1 = (int)Math.Round(Math.Min(DragStart.Y, DragCurrent.Y));
            int x2 = (int)Math.Round(Math.Max(DragStart.X, DragCurrent.X));
            int y2 = (int)Math.Round(Math.Max(DragStart.Y, DragCurrent.Y));
            return new Int32Rect(x1, y1, Math.Max(1, x2 - x1), Math.Max(1, y2 - y1));
        }
    }

    public void StartInteractive(CaptureMode mode, Action<CaptureResult> onDone)
    {
        if (IsActive) return;
        IsActive = true;
        _mode = mode;
        _onDone = onDone;
        Dragging = false;
        HasKeyboardSelection = false;
        HoveredWindow = null;

        (_frozen, _frozenBounds) = ScreenFreezer.CaptureVirtualScreen();
        // Window list is used by Window mode AND by Region mode's click-to-capture-window.
        _windows = WindowEnumerator.GetTopWindows();

        Native.GetCursorPos(out var cursor);
        PointerPhysical = new Point(cursor.X, cursor.Y);
        UpdateHover(PointerPhysical);

        foreach (var monitor in MonitorInfoProvider.GetMonitors())
        {
            bool containsCursor =
                cursor.X >= monitor.Bounds.X && cursor.X < monitor.Bounds.X + monitor.Bounds.Width &&
                cursor.Y >= monitor.Bounds.Y && cursor.Y < monitor.Bounds.Y + monitor.Bounds.Height;
            var overlay = new OverlayWindow(this, monitor, _frozen, _frozenBounds, activate: containsCursor);
            _overlays.Add(overlay);
            overlay.Show();
        }
    }

    // ---- Overlay callbacks ------------------------------------------------------

    internal void BeginDrag(Point physical)
    {
        Dragging = true;
        HasKeyboardSelection = false;
        DragStart = DragCurrent = physical;
        Repaint();
    }

    internal void UpdatePointer(Point physical)
    {
        PointerPhysical = physical;
        if (!Dragging) UpdateHover(physical);
        else DragCurrent = physical;
        Repaint();
    }

    private void UpdateHover(Point physical)
    {
        HoveredWindow = _windows?.FirstOrDefault(w =>
            physical.X >= w.Bounds.X && physical.X < w.Bounds.X + w.Bounds.Width &&
            physical.Y >= w.Bounds.Y && physical.Y < w.Bounds.Y + w.Bounds.Height);
    }

    internal void EndDrag(Point physical)
    {
        if (_mode == CaptureMode.Window)
        {
            if (HoveredWindow is { } win) CompleteWindow(win);
            else Cancel();
            return;
        }

        if (!Dragging) return; // drag was cancelled with Esc — the release must not close the overlay

        DragCurrent = physical;
        var rect = SelectionRect;
        if (rect.Width < 4 || rect.Height < 4)
        {
            Dragging = false;
            // A plain click captures the window under the cursor (spec: one hotkey, all modes).
            if (HoveredWindow is { } win) CompleteWindow(win);
            else Cancel();
            return;
        }
        CompleteRegion(rect);
    }

    /// <summary>Arrow-key capture: create/move (plain) or resize (Shift) the selection, 1px steps.</summary>
    internal void NudgeSelection(int dx, int dy, bool resize)
    {
        if (_mode != CaptureMode.Region || Dragging) return;
        if (!HasKeyboardSelection)
        {
            // Define a starter selection centered on the pointer.
            DragStart = new Point(PointerPhysical.X - 150, PointerPhysical.Y - 100);
            DragCurrent = new Point(PointerPhysical.X + 150, PointerPhysical.Y + 100);
            HasKeyboardSelection = true;
        }
        else if (resize)
        {
            DragCurrent = new Point(DragCurrent.X + dx, DragCurrent.Y + dy);
        }
        else
        {
            DragStart = new Point(DragStart.X + dx, DragStart.Y + dy);
            DragCurrent = new Point(DragCurrent.X + dx, DragCurrent.Y + dy);
        }
        Repaint();
    }

    internal void ConfirmSelection()
    {
        if (_mode != CaptureMode.Region) return;
        if (HasKeyboardSelection || Dragging)
        {
            var rect = SelectionRect;
            if (rect.Width >= 4 && rect.Height >= 4) CompleteRegion(rect);
        }
    }

    internal void Cancel()
    {
        CloseOverlays();
        Cleanup();
    }

    private void CompleteRegion(Int32Rect physicalRect)
    {
        var frozen = _frozen!;
        var bounds = _frozenBounds;
        var done = _onDone;
        CloseOverlays();
        var bmp = ScreenFreezer.Crop(frozen, bounds, physicalRect);
        Cleanup();
        var rect = new PixelRect(physicalRect.X, physicalRect.Y, physicalRect.Width, physicalRect.Height);
        done?.Invoke(new CaptureResult(bmp, CaptureMode.Region, rect, rect));
    }

    private void CompleteWindow(WindowEntry win)
    {
        var frozen = _frozen!;
        var bounds = _frozenBounds;
        var done = _onDone;
        CloseOverlays();

        // Prefer the window's own composited content (clean even when occluded);
        // fall back to cropping the frozen desktop.
        var bmp = WindowEnumerator.CaptureWindow(win)
                  ?? ScreenFreezer.Crop(frozen, bounds, win.Bounds);
        Cleanup();
        done?.Invoke(new CaptureResult(bmp, CaptureMode.Window, null,
            new PixelRect(win.Bounds.X, win.Bounds.Y, win.Bounds.Width, win.Bounds.Height)));
    }

    private void CloseOverlays()
    {
        foreach (var o in _overlays) o.CloseOverlay();
        _overlays.Clear();
    }

    private void Cleanup()
    {
        _frozen = null;
        _windows = null;
        _onDone = null;
        Dragging = false;
        HasKeyboardSelection = false;
        HoveredWindow = null;
        IsActive = false;
    }

    private void Repaint()
    {
        foreach (var o in _overlays) o.RepaintOverlay();
    }

    // ---- Non-interactive captures ---------------------------------------------------

    public CaptureResult? CaptureMonitor(int index)
    {
        var monitors = MonitorInfoProvider.GetMonitors();
        if (index < 0 || index >= monitors.Count) return null;
        var b = monitors[index].Bounds;
        var bmp = ScreenFreezer.CapturePhysicalRect(b);
        return new CaptureResult(bmp, CaptureMode.FullScreen, null,
            new PixelRect(b.X, b.Y, b.Width, b.Height));
    }

    public CaptureResult? CaptureRegionRect(PixelRect r)
    {
        var bmp = ScreenFreezer.CapturePhysicalRect(new Int32Rect(r.X, r.Y, r.Width, r.Height));
        return new CaptureResult(bmp, CaptureMode.Region, r, r);
    }
}
