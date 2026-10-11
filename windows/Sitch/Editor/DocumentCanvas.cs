using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Sitch.Core;

namespace Sitch.Editor;

/// <summary>
/// The annotation canvas. Renders the document at the current zoom, owns hit-testing,
/// selection handles, draft creation and crop-mode chrome. Zoom is "physical screen px
/// per document px", so 100% is always pixel-perfect regardless of monitor scale.
/// </summary>
public sealed class DocumentCanvas : FrameworkElement
{
    public Document? Doc { get; set; }
    public EditorWindow Owner { get; set; } = null!;

    public double Zoom { get; private set; } = 1.0;
    private double _dpi = 1.0;

    public ToolKind Tool { get; private set; } = ToolKind.Arrow;
    public Annotation? Selected { get; private set; }
    public Annotation? Draft { get; private set; }
    /// <summary>Annotation hidden from rendering while its TextBox overlay is active.</summary>
    public Annotation? EditingText { get; set; }

    public bool CropMode { get; private set; }
    public Rect CropDraft;   // doc px

    public event Action? SelectionChanged;
    public event Action? CropDraftChanged;

    // drag state
    private enum DragKind { None, Create, Move, Handle, CropHandle, CropMove }
    private DragKind _drag;
    private int _handleIndex = -1;
    private Point _dragStartDoc;
    private Rect _cropStart;
    private bool _undoPushed;

    private const double HandleHitDip = 7;

    public DocumentCanvas()
    {
        Focusable = true;
        SnapsToDevicePixels = true;
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
    }

    // ---- Geometry ------------------------------------------------------------------

    private Int32Rect View => CropMode
        ? new Int32Rect(0, 0, Doc?.Width ?? 1, Doc?.Height ?? 1)
        : Doc?.ViewRect ?? new Int32Rect(0, 0, 1, 1);

    private double DipPerDoc => Zoom / _dpi;

    public Point ToDoc(Point dip) => new(View.X + dip.X / DipPerDoc, View.Y + dip.Y / DipPerDoc);
    public Point ToDip(Point doc) => new((doc.X - View.X) * DipPerDoc, (doc.Y - View.Y) * DipPerDoc);
    public Rect ToDip(Rect doc) => new(ToDip(doc.TopLeft), ToDip(doc.BottomRight));

    public void SetDpi(double dpiScale)
    {
        _dpi = dpiScale;
        InvalidateMeasure();
        InvalidateVisual();
    }

    public void SetZoom(double zoom)
    {
        Zoom = Math.Clamp(zoom, 0.05, 8);
        InvalidateMeasure();
        InvalidateVisual();
        Owner?.OnZoomChanged();
    }

    public void SetTool(ToolKind tool)
    {
        Tool = tool;
        if (tool != ToolKind.Select) Select(null);
        Cursor = tool switch
        {
            ToolKind.Select => Cursors.Arrow,
            ToolKind.Text => Cursors.IBeam,
            _ => Cursors.Cross,
        };
        InvalidateVisual();
    }

    public void Select(Annotation? a)
    {
        if (ReferenceEquals(Selected, a)) return;
        Selected = a;
        SelectionChanged?.Invoke();
        InvalidateVisual();
    }

    public void EnterCropMode()
    {
        CropMode = true;
        var v = Doc!.ViewRect;
        // Everything selected by default (v1.2.2 behavior).
        CropDraft = new Rect(v.X, v.Y, v.Width, v.Height);
        Select(null);
        InvalidateMeasure();
        InvalidateVisual();
        CropDraftChanged?.Invoke();
    }

    public void ExitCropMode()
    {
        CropMode = false;
        InvalidateMeasure();
        InvalidateVisual();
    }

    protected override Size MeasureOverride(Size availableSize)
    {
        var v = View;
        return new Size(v.Width * DipPerDoc, v.Height * DipPerDoc);
    }

    // ---- Input --------------------------------------------------------------------

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        if (Doc is null) return;
        Focus();
        Owner.CommitTextEdit();

        var dip = e.GetPosition(this);
        var doc = ToDoc(dip);
        _dragStartDoc = doc;
        _undoPushed = false;

        if (CropMode)
        {
            _handleIndex = HitCropHandle(dip);
            if (_handleIndex >= 0) { _drag = DragKind.CropHandle; }
            else if (CropDraft.Contains(doc)) { _drag = DragKind.CropMove; _cropStart = CropDraft; }
            else _drag = DragKind.None;
            CaptureMouse();
            return;
        }

        switch (Tool)
        {
            case ToolKind.Select:
            {
                if (Selected is not null)
                {
                    int h = HitHandle(Selected, dip);
                    if (h >= 0)
                    {
                        _drag = DragKind.Handle;
                        _handleIndex = h;
                        CaptureMouse();
                        return;
                    }
                }
                var hit = TopmostHit(doc);
                Select(hit);
                if (hit is not null)
                {
                    if (e.ClickCount == 2 && hit is TextAnnotation t)
                    {
                        Owner.BeginTextEdit(t, isNew: false);
                        _drag = DragKind.None;
                        return;
                    }
                    _drag = DragKind.Move;
                    CaptureMouse();
                }
                break;
            }

            case ToolKind.Text:
                Owner.HandleTextToolClick(doc);
                break;

            case ToolKind.Stamp:
                Owner.PlaceStamp(doc);
                break;

            case ToolKind.Sticker:
                Owner.PlaceSticker(doc);
                break;

            case ToolKind.Image:
            case ToolKind.Crop:
                break; // handled by window chrome

            case ToolKind.Pen:
            case ToolKind.Highlight:
            {
                var pen = (PenAnnotation)Owner.MakeDraft(Tool, doc)!;
                pen.Points.Add(doc);
                Draft = pen;
                _drag = DragKind.Create;
                CaptureMouse();
                break;
            }

            default: // Arrow, Line, Rectangle, Ellipse, Obscure, Spotlight
            {
                Draft = Owner.MakeDraft(Tool, doc);
                _drag = Draft is not null ? DragKind.Create : DragKind.None;
                if (_drag == DragKind.Create) CaptureMouse();
                break;
            }
        }
        InvalidateVisual();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (Doc is null) return;
        var dip = e.GetPosition(this);
        var doc = ToDoc(dip);

        if (CropMode && _drag == DragKind.None)
        {
            Cursor = HitCropHandle(dip) >= 0 ? Cursors.SizeAll
                : CropDraft.Contains(doc) ? Cursors.SizeAll : Cursors.Arrow;
        }

        switch (_drag)
        {
            case DragKind.Create when Draft is PenAnnotation pen:
                if (pen.Points.Count == 0 || (doc - pen.Points[^1]).Length > 1.2)
                    pen.Points.Add(doc);
                break;

            case DragKind.Create when Draft is TwoPointAnnotation tp:
                tp.B = Shift(e) ? SnapAngle(tp.A, doc) : doc;
                break;

            case DragKind.Create when Draft is RectAnnotation ra:
                ra.B = Shift(e) ? SnapSquare(ra.A, doc) : doc;
                break;

            case DragKind.Move when Selected is not null:
                EnsureUndo();
                Selected.MoveBy(doc - _dragStartDoc);
                _dragStartDoc = doc;
                Doc.Dirty = true;
                break;

            case DragKind.Handle when Selected is not null:
                EnsureUndo();
                Selected.MoveHandle(_handleIndex, doc);
                Doc.Dirty = true;
                break;

            case DragKind.CropHandle:
                MoveCropHandle(_handleIndex, doc);
                CropDraftChanged?.Invoke();
                break;

            case DragKind.CropMove:
            {
                var d = doc - _dragStartDoc;
                var r = new Rect(_cropStart.X + d.X, _cropStart.Y + d.Y, _cropStart.Width, _cropStart.Height);
                r.X = Math.Clamp(r.X, 0, Math.Max(0, Doc.Width - r.Width));
                r.Y = Math.Clamp(r.Y, 0, Math.Max(0, Doc.Height - r.Height));
                CropDraft = r;
                CropDraftChanged?.Invoke();
                break;
            }

            default:
                return;
        }
        InvalidateVisual();
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        if (IsMouseCaptured) ReleaseMouseCapture();

        if (_drag == DragKind.Create && Draft is not null && Doc is not null)
        {
            bool valid = Draft switch
            {
                PenAnnotation p => p.Points.Count >= 2 && p.Bounds is { Width: > 2 } or { Height: > 2 },
                TwoPointAnnotation tp => (tp.B - tp.A).Length >= 4,
                RectAnnotation ra => ra.Rect.Width >= 4 && ra.Rect.Height >= 4,
                _ => true,
            };
            if (valid)
            {
                Doc.Add(Draft);
                if (Tool is ToolKind.Obscure or ToolKind.Spotlight or ToolKind.Rectangle
                    or ToolKind.Ellipse or ToolKind.Arrow or ToolKind.Line)
                {
                    // Keep the tool armed (Skitch flow) but select the new mark for quick tweaks.
                }
            }
            Draft = null;
        }
        _drag = DragKind.None;
        _handleIndex = -1;
        InvalidateVisual();
    }

    protected override void OnMouseWheel(MouseWheelEventArgs e)
    {
        base.OnMouseWheel(e);
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control))
        {
            Owner.NudgeZoom(e.Delta > 0 ? 1.15 : 1 / 1.15);
            e.Handled = true;
        }
    }

    private void EnsureUndo()
    {
        if (_undoPushed || Doc is null) return;
        Doc.PushUndo();
        _undoPushed = true;
    }

    private static bool Shift(MouseEventArgs e) => Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);

    private static Point SnapAngle(Point a, Point b)
    {
        var v = b - a;
        double ang = Math.Atan2(v.Y, v.X);
        double snap = Math.Round(ang / (Math.PI / 4)) * (Math.PI / 4);
        double len = v.Length;
        return a + new Vector(Math.Cos(snap), Math.Sin(snap)) * len;
    }

    private static Point SnapSquare(Point a, Point b)
    {
        double s = Math.Max(Math.Abs(b.X - a.X), Math.Abs(b.Y - a.Y));
        return new Point(a.X + Math.Sign(b.X - a.X) * s, a.Y + Math.Sign(b.Y - a.Y) * s);
    }

    private Annotation? TopmostHit(Point doc)
    {
        if (Doc is null) return null;
        for (int i = Doc.Annotations.Count - 1; i >= 0; i--)
            if (Doc.Annotations[i].HitTest(doc))
                return Doc.Annotations[i];
        return null;
    }

    private int HitHandle(Annotation a, Point dip)
    {
        var handles = a.GetHandles();
        for (int i = 0; i < handles.Count; i++)
            if ((ToDip(handles[i]) - dip).Length <= HandleHitDip)
                return i;
        return -1;
    }

    // ---- Crop dragging --------------------------------------------------------------

    private IReadOnlyList<Point> CropHandles()
    {
        var r = CropDraft;
        return
        [
            r.TopLeft, r.TopRight, r.BottomRight, r.BottomLeft,
            new(r.X + r.Width / 2, r.Y), new(r.Right, r.Y + r.Height / 2),
            new(r.X + r.Width / 2, r.Bottom), new(r.X, r.Y + r.Height / 2),
        ];
    }

    private int HitCropHandle(Point dip)
    {
        var handles = CropHandles();
        for (int i = 0; i < handles.Count; i++)
            if ((ToDip(handles[i]) - dip).Length <= HandleHitDip + 2)
                return i;
        return -1;
    }

    private void MoveCropHandle(int index, Point doc)
    {
        if (Doc is null) return;
        doc.X = Math.Clamp(doc.X, 0, Doc.Width);
        doc.Y = Math.Clamp(doc.Y, 0, Doc.Height);
        double left = CropDraft.Left, top = CropDraft.Top, right = CropDraft.Right, bottom = CropDraft.Bottom;
        switch (index)
        {
            case 0: left = doc.X; top = doc.Y; break;
            case 1: right = doc.X; top = doc.Y; break;
            case 2: right = doc.X; bottom = doc.Y; break;
            case 3: left = doc.X; bottom = doc.Y; break;
            case 4: top = doc.Y; break;
            case 5: right = doc.X; break;
            case 6: bottom = doc.Y; break;
            case 7: left = doc.X; break;
        }
        double ratio = Owner.CropAspectRatio;
        if (ratio > 0)
        {
            if (index < 4)
            {
                // Corners: width drives; clamp the derived height to the space on the
                // anchored side and pull the dragged edge back so the ratio survives.
                double w = Math.Abs(right - left);
                double h = w / ratio;
                double availH = index is 0 or 1 ? bottom : Doc.Height - top;
                if (h > availH)
                {
                    h = Math.Max(1, availH);
                    w = h * ratio;
                    int sx = right >= left ? 1 : -1;
                    if (index is 1 or 2) right = left + sx * w; else left = right - sx * w;
                }
                if (index is 0 or 1) top = bottom - h; else bottom = top + h;
            }
            else if (index is 5 or 7)
            {
                // Vertical edges: width drives, symmetric about the vertical center.
                double w = Math.Abs(right - left);
                double h = w / ratio;
                double cy = (top + bottom) / 2;
                double maxH = Math.Max(1, Math.Min(cy, Doc.Height - cy) * 2);
                if (h > maxH)
                {
                    h = maxH;
                    w = h * ratio;
                    if (index == 5) right = left + w; else left = right - w;
                }
                top = cy - h / 2;
                bottom = cy + h / 2;
            }
            else
            {
                // Horizontal edges: height drives, symmetric about the horizontal center.
                double h = Math.Abs(bottom - top);
                double w = h * ratio;
                double cx = (left + right) / 2;
                double maxW = Math.Max(1, Math.Min(cx, Doc.Width - cx) * 2);
                if (w > maxW)
                {
                    w = maxW;
                    h = w / ratio;
                    if (index == 6) bottom = top + h; else top = bottom - h;
                }
                left = cx - w / 2;
                right = cx + w / 2;
            }
        }
        var draft = new Rect(new Point(Math.Min(left, right), Math.Min(top, bottom)),
                             new Point(Math.Max(left, right), Math.Max(top, bottom)));
        // Never let the preview extend past the document — Apply must crop what was shown.
        draft.Intersect(new Rect(0, 0, Doc.Width, Doc.Height));
        if (draft.IsEmpty || draft.Width < 1 || draft.Height < 1) return;
        CropDraft = draft;
    }

    public void SetCropDraft(Rect r)
    {
        CropDraft = r;
        InvalidateVisual();
    }

    // ---- Rendering -------------------------------------------------------------------

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        if (Doc is null) return;

        var v = View;
        double s = DipPerDoc;

        dc.PushTransform(new ScaleTransform(s, s));
        dc.PushTransform(new TranslateTransform(-v.X, -v.Y));
        dc.PushClip(new RectangleGeometry(new Rect(v.X, v.Y, v.Width, v.Height)));

        Renderer.Draw(dc, Doc, forExport: false, skip: EditingText);
        Draft?.Render(dc, new RenderContext { Base = Doc.Base, BaseVersion = Doc.BaseVersion });

        dc.Pop(); dc.Pop(); dc.Pop();

        // Screen-space chrome (constant size regardless of zoom)
        if (CropMode) RenderCropChrome(dc);
        else if (Selected is not null && !ReferenceEquals(Selected, EditingText)) RenderSelection(dc, Selected);
    }

    private void RenderSelection(DrawingContext dc, Annotation a)
    {
        var b = ToDip(a.Bounds);
        var dash = new Pen(new SolidColorBrush(Color.FromArgb(0xC8, 0xFF, 0x33, 0x66)), 1) { DashStyle = DashStyles.Dash };
        dc.DrawRectangle(null, dash, b);
        foreach (var h in a.GetHandles())
            DrawHandle(dc, ToDip(h));
    }

    private void RenderCropChrome(DrawingContext dc)
    {
        var full = new Rect(0, 0, ActualWidth, ActualHeight);
        var sel = ToDip(CropDraft);
        var dim = new CombinedGeometry(GeometryCombineMode.Exclude,
            new RectangleGeometry(full), new RectangleGeometry(sel));
        dc.DrawGeometry(new SolidColorBrush(Color.FromArgb(0x8C, 0, 0, 0)), null, dim);

        var thin = new Pen(new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF)), 1);
        dc.DrawRectangle(null, thin, sel);
        // Rule-of-thirds grid.
        for (int i = 1; i <= 2; i++)
        {
            double x = sel.X + sel.Width * i / 3;
            double y = sel.Y + sel.Height * i / 3;
            dc.DrawLine(thin, new Point(x, sel.Top), new Point(x, sel.Bottom));
            dc.DrawLine(thin, new Point(sel.Left, y), new Point(sel.Right, y));
        }
        foreach (var h in CropHandles())
            DrawHandle(dc, ToDip(h));
    }

    private static void DrawHandle(DrawingContext dc, Point center)
    {
        var pen = new Pen(new SolidColorBrush(Color.FromRgb(0xFF, 0x33, 0x66)), 1.4);
        dc.DrawRectangle(Brushes.White, pen, new Rect(center.X - 4.5, center.Y - 4.5, 9, 9));
    }
}
