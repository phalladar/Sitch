using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Sitch.Core;

public enum RotateFlipKind { RotateLeft, RotateRight, FlipHorizontal, FlipVertical }

/// <summary>
/// One editing document: an immutable pristine capture + an ordered list of annotation
/// objects + a non-destructive crop. Undo/redo is whole-state snapshots (simple and correct;
/// per-op commands can come later).
/// </summary>
public sealed class Document
{
    private sealed record State(
        BitmapSource Base, int BaseVersion, List<Annotation> Annotations,
        Int32Rect? Crop, int NextStampNumber);

    private readonly Stack<State> _undo = new();
    private readonly Stack<State> _redo = new();
    private const int MaxUndo = 100;

    public BitmapSource Base { get; private set; }
    public int BaseVersion { get; private set; }
    public List<Annotation> Annotations { get; } = new();
    public Int32Rect? Crop { get; private set; }
    public int NextStampNumber { get; set; } = 1;
    public bool Dirty { get; set; }

    public event Action? Changed;

    public Document(BitmapSource baseBitmap)
    {
        Base = baseBitmap;
    }

    public int Width => Base.PixelWidth;
    public int Height => Base.PixelHeight;

    /// <summary>The visible viewport (crop applied), in doc pixels.</summary>
    public Int32Rect ViewRect => Crop ?? new Int32Rect(0, 0, Width, Height);

    public bool CanUndo => _undo.Count > 0;
    public bool CanRedo => _redo.Count > 0;

    public void NotifyChanged() => Changed?.Invoke();

    /// <summary>Take an undo snapshot BEFORE a mutation (add/delete/move/crop/rotate…).</summary>
    public void PushUndo()
    {
        _undo.Push(Snapshot());
        if (_undo.Count > MaxUndo)
        {
            // Drop the oldest state.
            var keep = _undo.Take(MaxUndo).ToArray();
            _undo.Clear();
            for (int i = keep.Length - 1; i >= 0; i--) _undo.Push(keep[i]);
        }
        _redo.Clear();
    }

    public void Undo()
    {
        if (_undo.Count == 0) return;
        _redo.Push(Snapshot());
        Restore(_undo.Pop());
    }

    public void Redo()
    {
        if (_redo.Count == 0) return;
        _undo.Push(Snapshot());
        Restore(_redo.Pop());
    }

    private State Snapshot() => new(
        Base, BaseVersion, Annotations.Select(a => a.Clone()).ToList(), Crop, NextStampNumber);

    private void Restore(State s)
    {
        Base = s.Base;
        BaseVersion = s.BaseVersion;
        Annotations.Clear();
        Annotations.AddRange(s.Annotations.Select(a => a.Clone()));
        Crop = s.Crop;
        NextStampNumber = s.NextStampNumber;
        Dirty = true;
        NotifyChanged();
    }

    // ---- Mutations -----------------------------------------------------------------

    public void Add(Annotation a)
    {
        PushUndo();
        Annotations.Add(a);
        Dirty = true;
        NotifyChanged();
    }

    public void Remove(Annotation a)
    {
        PushUndo();
        Annotations.Remove(a);
        Dirty = true;
        NotifyChanged();
    }

    public void ApplyCrop(Int32Rect rect)
    {
        PushUndo();
        rect.X = Math.Clamp(rect.X, 0, Math.Max(0, Width - 1));
        rect.Y = Math.Clamp(rect.Y, 0, Math.Max(0, Height - 1));
        rect.Width = Math.Clamp(rect.Width, 1, Width - rect.X);
        rect.Height = Math.Clamp(rect.Height, 1, Height - rect.Y);
        Crop = rect.Width >= Width && rect.Height >= Height ? null : rect;
        Dirty = true;
        NotifyChanged();
    }

    public void RotateFlip(RotateFlipKind kind)
    {
        PushUndo();
        int w = Width, h = Height;

        Transform t = kind switch
        {
            RotateFlipKind.RotateLeft => new RotateTransform(-90),
            RotateFlipKind.RotateRight => new RotateTransform(90),
            RotateFlipKind.FlipHorizontal => new ScaleTransform(-1, 1),
            _ => new ScaleTransform(1, -1),
        };
        var tb = new TransformedBitmap(Base, t);
        var frozen = BitmapFrame.Create(tb);
        frozen.Freeze();
        Base = frozen;
        BaseVersion++;

        // Annotations follow the image (spec: "Rotate left/right and flip — annotations follow").
        Func<Point, Point> map = kind switch
        {
            RotateFlipKind.RotateLeft => p => new Point(p.Y, w - p.X),
            RotateFlipKind.RotateRight => p => new Point(h - p.Y, p.X),
            RotateFlipKind.FlipHorizontal => p => new Point(w - p.X, p.Y),
            _ => p => new Point(p.X, h - p.Y),
        };
        foreach (var a in Annotations) a.ApplyTransform(map);

        if (Crop is { } c)
        {
            var p1 = map(new Point(c.X, c.Y));
            var p2 = map(new Point(c.X + c.Width, c.Y + c.Height));
            var r = new Rect(p1, p2);
            Crop = new Int32Rect((int)r.X, (int)r.Y, (int)r.Width, (int)r.Height);
        }

        Dirty = true;
        NotifyChanged();
    }
}
