using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using WinSitch.Capture;
using WinSitch.Core;
using IOPath = System.IO.Path;
using WinSitch.Export;
using WinSitch.Shell;

namespace WinSitch.Editor;

public partial class EditorWindow : Window
{
    private readonly Document _doc;
    private readonly string _docName;
    private readonly MonitorData? _targetMonitor;
    private IntPtr _hwnd;
    private double _dpi = 1.0;
    /// <summary>Suppresses change-handlers while the top bar is synced FROM a selection.</summary>
    private bool _syncingSelection;

    // ---- current style state -------------------------------------------------
    private Color _color;
    private ArrowStyle _arrowStyle = ArrowStyle.Tapered;
    private bool _arrowDouble;
    private bool _shapeFilled;
    private ObscureStyle _obscureStyle;
    private StampKind _stampKind = StampKind.Check;
    private string _emoji = "😀";
    private string _fontFamily;
    private double _fontSize;
    private bool _bold = true, _italic;
    private string _saveFormat;

    private readonly Dictionary<ToolKind, RadioButton> _railButtons = new();
    private readonly List<ToggleButton> _widthButtons = new();
    private static readonly double[] WidthPresetValues = [2, 4, 8, 16, 28];

    private static readonly string[] PaletteHex =
        ["#FF3366", "#FF9500", "#FFD60A", "#34C759", "#2E7DF6", "#5E5CE6", "#AF52DE", "#1D1D1F", "#FFFFFF"];

    // text editing overlay state
    private TextAnnotation? _editing;
    private bool _editingIsNew;

    // crop state
    private bool _syncingCrop;
    private double _lockedRatio;
    public double CropAspectRatio { get; private set; }

    private readonly List<string> _tempFiles = new();
    private bool _closeConfirmed;

    public EditorWindow(BitmapSource bitmap, string title, PixelRect? sourceRect = null)
    {
        InitializeComponent();
        _docName = string.IsNullOrWhiteSpace(title) ? "Untitled" : title;

        // v1.4.0 parity: open on the display the capture came from.
        if (sourceRect is { } src)
        {
            double cx = src.X + src.Width / 2.0, cy = src.Y + src.Height / 2.0;
            _targetMonitor = MonitorInfoProvider.GetMonitors().FirstOrDefault(m =>
                cx >= m.Bounds.X && cx < m.Bounds.X + m.Bounds.Width &&
                cy >= m.Bounds.Y && cy < m.Bounds.Y + m.Bounds.Height);
        }
        Title = $"{_docName} — WinSitch";
        ShowInTaskbar = App.Settings.ShowInTaskbar;
        Icon = new BitmapImage(new Uri("pack://application:,,,/Assets/winsitch.ico"));

        _doc = new Document(bitmap);
        _color = ParseColor(App.Settings.DefaultColor, "#FF3366");
        _fontFamily = App.Settings.FontFamily;
        _fontSize = App.Settings.TextSize;
        _obscureStyle = Enum.TryParse<ObscureStyle>(App.Settings.ObscureStyle, out var os) ? os : ObscureStyle.Pixelate;
        _saveFormat = Exporters.Formats.Contains(App.Settings.DefaultFormat) ? App.Settings.DefaultFormat : "png";

        Canvas.Doc = _doc;
        Canvas.Owner = this;
        _doc.Changed += OnDocChanged;
        Canvas.SelectionChanged += OnSelectionChanged;
        Canvas.CropDraftChanged += SyncCropFieldsFromDraft;

        BuildRail();
        BuildSwatches();
        BuildWidthPresets();
        BuildArrowStyleIcons();
        BuildTextControls();
        BuildAspectCombo();
        BuildCanvasContextMenu();
        WireChrome();

        var startTool = App.Settings.RememberLastTool &&
                        Enum.TryParse<ToolKind>(App.Settings.LastTool, out var lt) &&
                        lt is not (ToolKind.Crop or ToolKind.Image)
            ? lt : ToolKind.Arrow;
        _railButtons[startTool].IsChecked = true;

        SourceInitialized += OnSourceInit;
        Closing += OnClosingPrompt;
        Closed += (_, _) =>
        {
            Export.ShareHelper.Detach(_hwnd); // don't root the share manager for a dead window
            CleanupTempFiles();
        };
        PreviewKeyDown += OnPreviewKey;
        UpdateBottom();
    }

    private void OnSourceInit(object? sender, EventArgs e)
    {
        _hwnd = new System.Windows.Interop.WindowInteropHelper(this).Handle;

        // Land on the source display BEFORE reading DPI (WM_DPICHANGED is synchronous under PMv2).
        if (_targetMonitor is { } tm)
            Native.SetWindowPos(_hwnd, IntPtr.Zero, tm.WorkArea.X + 48, tm.WorkArea.Y + 48, 0, 0,
                Native.SWP_NOSIZE | Native.SWP_NOZORDER | Native.SWP_NOACTIVATE);

        _dpi = VisualTreeHelper.GetDpi(this).DpiScaleX;
        Canvas.SetDpi(_dpi);

        var (waW, waH) = WorkAreaDip();

        // Returning users get the window size they last closed with (Windows convention);
        // the capture scales to fit inside it — or shows at 100% if it fits.
        if (App.Settings.EditorWidth >= MinWidth && App.Settings.EditorHeight >= MinHeight)
        {
            Width = Math.Min(App.Settings.EditorWidth, waW * 0.98);
            Height = Math.Min(App.Settings.EditorHeight, waH * 0.98);
            if (App.Settings.EditorMaximized) WindowState = WindowState.Maximized;
            ClampToWorkArea();
            Dispatcher.BeginInvoke(ChooseZoomForViewport, System.Windows.Threading.DispatcherPriority.Loaded);
            return;
        }

        // First-ever editor: open sized to the capture at 100% when it fits (v1.4.0 parity).
        double chromeW = 46 + 40, chromeH = 44 + 40 + 42 + 36; // rail + margins, bars + titlebar
        double docW = _doc.ViewRect.Width / _dpi, docH = _doc.ViewRect.Height / _dpi;
        if (docW + chromeW < waW * 0.95 && docH + chromeH < waH * 0.95)
        {
            Width = Math.Max(MinWidth, docW + chromeW);
            Height = Math.Max(MinHeight, docH + chromeH);
            Canvas.SetZoom(1.0);
            Dispatcher.BeginInvoke(AdjustToFit, System.Windows.Threading.DispatcherPriority.Loaded);
        }
        else
        {
            Width = waW * 0.85;
            Height = waH * 0.85;
            ClampToWorkArea();
            Dispatcher.BeginInvoke(FitZoom, System.Windows.Threading.DispatcherPriority.Loaded);
        }
    }

    /// <summary>Within a remembered window: 100% when the capture fits, otherwise zoom-to-fit.</summary>
    private void ChooseZoomForViewport()
    {
        UpdateLayout();
        var v = _doc.ViewRect;
        double availW = Math.Max(80, Scroller.ViewportWidth - CanvasHost.Margin.Left - CanvasHost.Margin.Right) * _dpi;
        double availH = Math.Max(80, Scroller.ViewportHeight - CanvasHost.Margin.Top - CanvasHost.Margin.Bottom) * _dpi;
        if (v.Width <= availW && v.Height <= availH) Canvas.SetZoom(1.0);
        else FitZoom();
    }

    /// <summary>The relevant display's work area in this window's DIP units.</summary>
    private (double W, double H) WorkAreaDip()
    {
        var mon = _targetMonitor ?? CurrentMonitor();
        return mon is { } m
            ? (m.WorkArea.Width / _dpi, m.WorkArea.Height / _dpi)
            : (SystemParameters.WorkArea.Width, SystemParameters.WorkArea.Height);
    }

    private MonitorData? CurrentMonitor()
    {
        if (_hwnd == IntPtr.Zero) return null;
        var hMon = Native.MonitorFromWindow(_hwnd, Native.MONITOR_DEFAULTTONEAREST);
        return MonitorInfoProvider.GetMonitors().FirstOrDefault(m => m.Handle == hMon);
    }

    /// <summary>Keeps the whole window inside its display's work area (physical px, DPI-proof).</summary>
    private void ClampToWorkArea()
    {
        if (_hwnd == IntPtr.Zero) return;
        var mon = _targetMonitor ?? CurrentMonitor();
        if (mon is not { } m) return;
        if (!Native.GetWindowRect(_hwnd, out var r)) return;
        int w = r.Right - r.Left, h = r.Bottom - r.Top;
        int x = Math.Max(m.WorkArea.X, Math.Min(r.Left, m.WorkArea.X + m.WorkArea.Width - w));
        int y = Math.Max(m.WorkArea.Y, Math.Min(r.Top, m.WorkArea.Y + m.WorkArea.Height - h));
        if (x != r.Left || y != r.Top)
            Native.SetWindowPos(_hwnd, IntPtr.Zero, x, y, 0, 0,
                Native.SWP_NOSIZE | Native.SWP_NOZORDER | Native.SWP_NOACTIVATE);
    }

    /// <summary>Grow the window just enough that the canvas fits scrollbar-free at 100%.</summary>
    private void AdjustToFit()
    {
        UpdateLayout();
        var (waW, waH) = WorkAreaDip();
        double needW = CanvasHost.ActualWidth + CanvasHost.Margin.Left + CanvasHost.Margin.Right + 2;
        double needH = CanvasHost.ActualHeight + CanvasHost.Margin.Top + CanvasHost.Margin.Bottom + 2;
        double dw = needW - Scroller.ViewportWidth;
        double dh = needH - Scroller.ViewportHeight;
        if (dw > 0)
        {
            if (Width + dw <= waW * 0.98) Width += dw;
            else { FitZoom(); ClampToWorkArea(); return; }
        }
        if (dh > 0)
        {
            if (Height + dh <= waH * 0.98) Height += dh;
            else FitZoom();
        }
        ClampToWorkArea();
    }

    protected override void OnDpiChanged(DpiScale oldDpi, DpiScale newDpi)
    {
        base.OnDpiChanged(oldDpi, newDpi);
        if (_editing is not null) CommitTextEdit();
        _dpi = newDpi.DpiScaleX;
        Canvas.SetDpi(_dpi);
    }

    // ============================ chrome wiring =================================

    private void WireChrome()
    {
        BtnNewCapture.Click += (_, _) => App.Current.CaptureRegion();
        BtnUndo.Click += (_, _) => { CommitTextEdit(); _doc.Undo(); };
        BtnRedo.Click += (_, _) => { CommitTextEdit(); _doc.Redo(); };
        BtnTrash.Click += (_, _) => TrashClicked();
        BtnZoomOut.Click += (_, _) => NudgeZoom(1 / 1.25);
        BtnZoomIn.Click += (_, _) => NudgeZoom(1.25);
        BtnZoomLabel.Click += (_, _) => ShowZoomMenu();
        BtnCopy.Click += (_, _) => CopyImage();
        BtnSave.Click += (_, _) => ShowSaveMenu();
        BtnShare.Click += (_, _) => ShareImage();
        BtnDragOut.PreviewMouseLeftButtonDown += (_, _) => StartDragOut();
        ColorWell.MouseLeftButtonDown += (_, _) => ShowColorPicker(ColorWell);
        EmojiButton.Click += (_, _) => ShowEmojiPicker();

        PxField.LostFocus += (_, _) => CommitPxField();
        PxField.KeyDown += (_, e) => { if (e.Key == Key.Enter) { CommitPxField(); Keyboard.ClearFocus(); } };

        ArrowTapered.Click += (_, _) => SetArrowStyle(ArrowStyle.Tapered);
        ArrowFilled.Click += (_, _) => SetArrowStyle(ArrowStyle.Filled);
        ArrowOpen.Click += (_, _) => SetArrowStyle(ArrowStyle.Open);
        ArrowConcave.Click += (_, _) => SetArrowStyle(ArrowStyle.Concave);
        ArrowDouble.Click += (_, _) => { _arrowDouble = ArrowDouble.IsChecked == true; ApplyToSelected(a => { if (a is ArrowAnnotation ar) ar.DoubleHeaded = _arrowDouble; }); };

        OutlineToggle.Click += (_, _) => SetFilled(false);
        FilledToggle.Click += (_, _) => SetFilled(true);

        ObPixelate.Click += (_, _) => SetObscure(ObscureStyle.Pixelate);
        ObBlur.Click += (_, _) => SetObscure(ObscureStyle.Blur);
        ObBlock.Click += (_, _) => SetObscure(ObscureStyle.Block);
        ObStripes.Click += (_, _) => SetObscure(ObscureStyle.Stripes);

        StampCheck.Click += (_, _) => SetStamp(StampKind.Check);
        StampCross.Click += (_, _) => SetStamp(StampKind.Cross);
        StampStar.Click += (_, _) => SetStamp(StampKind.Star);
        StampDot.Click += (_, _) => SetStamp(StampKind.Dot);
        StampNumber.Click += (_, _) => SetStamp(StampKind.Number);

        CropCancel.Click += (_, _) => ExitCrop(apply: false);
        CropApply.Click += (_, _) => ExitCrop(apply: true);
        CropW.TextChanged += (_, _) => CropFieldEdited(widthEdited: true);
        CropH.TextChanged += (_, _) => CropFieldEdited(widthEdited: false);
        LockToggle.Click += (_, _) => UpdateLock();

        EditBox.LostKeyboardFocus += (_, e) =>
        {
            // Focus moving into the font controls is a mid-edit restyle, not a commit.
            if (IsWithinFontControls(e.NewFocus as DependencyObject)) return;
            CommitTextEdit();
        };
        EditBox.PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter && !Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))
            {
                CommitTextEdit();
                e.Handled = true;
            }
            else if (e.Key == Key.Escape)
            {
                CancelTextEdit();
                e.Handled = true;
            }
        };
    }

    private void BuildRail()
    {
        foreach (var (kind, name) in ToolIcons.RailOrder)
        {
            var rb = new RadioButton
            {
                Style = (Style)FindResource("RailTool"),
                GroupName = "tools",
                Content = ToolIcons.Create(kind),
                ToolTip = name,
            };
            rb.Checked += (_, _) => OnToolSelected(kind);
            _railButtons[kind] = rb;
            RailPanel.Children.Add(rb);
        }
        CropIconHost.Content = ToolIcons.Create(ToolKind.Crop);
        ColorWell.Fill = new SolidColorBrush(_color);
    }

    private void BuildSwatches()
    {
        foreach (var hex in PaletteHex)
        {
            var c = ParseColor(hex, "#FF3366");
            var b = new Button
            {
                Style = (Style)FindResource("IconButton"),
                Padding = new Thickness(3),
                ToolTip = hex,
                Content = new Ellipse
                {
                    Width = 16, Height = 16,
                    Fill = new SolidColorBrush(c),
                    Stroke = new SolidColorBrush(Color.FromArgb(0x50, 0x80, 0x80, 0x88)),
                    StrokeThickness = 1,
                },
            };
            b.Click += (_, _) => SetColor(c);
            SwatchPanel.Children.Add(b);
        }
        // Rainbow custom-picker button with a pink center dot.
        var wheel = new Grid { Width = 16, Height = 16 };
        var ring = new Ellipse
        {
            Width = 16, Height = 16,
            Fill = new LinearGradientBrush(new GradientStopCollection
            {
                new(Colors.Red, 0), new(Colors.Orange, 0.18), new(Colors.Yellow, 0.35),
                new(Colors.LimeGreen, 0.52), new(Colors.DeepSkyBlue, 0.7), new(Colors.MediumPurple, 0.86),
                new(Colors.Red, 1),
            }, 45),
        };
        wheel.Children.Add(ring);
        wheel.Children.Add(new Ellipse
        {
            Width = 6, Height = 6,
            Fill = new SolidColorBrush(ParseColor("#FF3366", "#FF3366")),
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
        });
        var custom = new Button
        {
            Style = (Style)FindResource("IconButton"),
            Padding = new Thickness(3),
            ToolTip = "Custom color…",
            Content = wheel,
        };
        custom.Click += (_, _) => ShowColorPicker(custom);
        SwatchPanel.Children.Add(custom);
    }

    private void BuildWidthPresets()
    {
        foreach (var value in WidthPresetValues)
        {
            var tb = new ToggleButton
            {
                Style = (Style)FindResource("SegToggle"),
                ToolTip = $"{value} px",
                Tag = value,
                Content = new Border
                {
                    Width = 18,
                    Height = Math.Clamp(value * 0.75, 2, 14),
                    CornerRadius = new CornerRadius(Math.Clamp(value * 0.35, 1, 7)),
                    Background = new SolidColorBrush(Color.FromRgb(0xC9, 0xC9, 0xCE)),
                },
            };
            tb.Click += (_, _) => { SetWidth(value); };
            _widthButtons.Add(tb);
            WidthPresets.Children.Add(tb);
        }
        // Bind preset bars to the toggle's Foreground so checked state tints them pink.
        foreach (var tb in _widthButtons)
            ((Border)tb.Content).SetBinding(Border.BackgroundProperty,
                new System.Windows.Data.Binding("Foreground") { Source = tb });
    }

    private void BuildArrowStyleIcons()
    {
        ArrowTapered.Content = ToolIcons.ArrowStyleIcon(ArrowStyle.Tapered);
        ArrowFilled.Content = ToolIcons.ArrowStyleIcon(ArrowStyle.Filled);
        ArrowOpen.Content = ToolIcons.ArrowStyleIcon(ArrowStyle.Open);
        ArrowConcave.Content = ToolIcons.ArrowStyleIcon(ArrowStyle.Concave);
        ArrowDouble.Content = ToolIcons.DoubleArrowIcon();
    }

    private void BuildTextControls()
    {
        var families = Fonts.SystemFontFamilies
            .Select(f => f.Source).OrderBy(s => s, StringComparer.OrdinalIgnoreCase).ToList();
        FontCombo.ItemsSource = families;
        FontCombo.SelectedItem = families.Contains(_fontFamily) ? _fontFamily : "Segoe UI";
        FontCombo.SelectionChanged += (_, _) =>
        {
            if (_syncingSelection) return;
            if (FontCombo.SelectedItem is string f)
            {
                _fontFamily = f;
                ApplyToSelected(a => { if (a is TextAnnotation t) t.FontFamily = f; });
                if (_editing is not null)
                {
                    EditBox.FontFamily = new FontFamily(f);
                    EditBox.Focus(); // resume the edit session
                }
            }
        };

        FontSizeCombo.ItemsSource = new double[] { 12, 14, 16, 20, 24, 28, 34, 40, 48, 64, 80, 96 };
        FontSizeCombo.Text = _fontSize.ToString();
        FontSizeCombo.SelectionChanged += (_, _) => CommitFontSize();
        FontSizeCombo.LostFocus += (_, _) => CommitFontSize();

        BoldToggle.IsChecked = _bold;
        BoldToggle.Click += (_, _) =>
        {
            _bold = BoldToggle.IsChecked == true;
            ApplyToSelected(a => { if (a is TextAnnotation t) t.Bold = _bold; });
            if (_editing is not null) EditBox.FontWeight = _bold ? FontWeights.Bold : FontWeights.Normal;
        };
        ItalicToggle.Click += (_, _) =>
        {
            _italic = ItalicToggle.IsChecked == true;
            ApplyToSelected(a => { if (a is TextAnnotation t) t.Italic = _italic; });
            if (_editing is not null) EditBox.FontStyle = _italic ? FontStyles.Italic : FontStyles.Normal;
        };
    }

    private void CommitFontSize()
    {
        if (_syncingSelection) return;
        double size = _fontSize;
        if (FontSizeCombo.SelectedItem is double d) size = d;
        else if (double.TryParse(FontSizeCombo.Text, out var p)) size = p;
        _fontSize = Math.Clamp(size, 6, 300);
        ApplyToSelected(a => { if (a is TextAnnotation t) t.FontSize = _fontSize; });
        if (_editing is not null)
        {
            EditBox.FontSize = _fontSize * Canvas.Zoom / _dpi;
            EditBox.Focus();
        }
    }

    /// <summary>True when focus target is inside FontCombo/FontSizeCombo (incl. their Popup items).</summary>
    private bool IsWithinFontControls(DependencyObject? d)
    {
        while (d is not null)
        {
            if (ReferenceEquals(d, FontCombo) || ReferenceEquals(d, FontSizeCombo)) return true;
            var next = d is System.Windows.Media.Visual or System.Windows.Media.Media3D.Visual3D
                ? VisualTreeHelper.GetParent(d)
                : LogicalTreeHelper.GetParent(d);
            d = next ?? LogicalTreeHelper.GetParent(d);
        }
        return false;
    }

    private void BuildAspectCombo()
    {
        (string Label, double Ratio)[] presets =
            [("Free", 0), ("Original", -1), ("1:1", 1), ("4:3", 4.0 / 3), ("3:2", 1.5), ("16:9", 16.0 / 9)];
        foreach (var (label, ratio) in presets)
            AspectCombo.Items.Add(new ComboBoxItem { Content = label, Tag = ratio });
        AspectCombo.SelectedIndex = 0;
        AspectCombo.SelectionChanged += (_, _) =>
        {
            if (AspectCombo.SelectedItem is not ComboBoxItem item) return;
            double r = (double)item.Tag;
            CropAspectRatio = r < 0 ? (double)_doc.Width / _doc.Height : r;
            if (CropAspectRatio > 0) ReshapeCropToRatio(CropAspectRatio);
        };
    }

    private void BuildCanvasContextMenu()
    {
        var menu = new ContextMenu();
        menu.Items.Add(MenuItemFor("Rotate Left", () => _doc.RotateFlip(RotateFlipKind.RotateLeft)));
        menu.Items.Add(MenuItemFor("Rotate Right", () => _doc.RotateFlip(RotateFlipKind.RotateRight)));
        menu.Items.Add(MenuItemFor("Flip Horizontal", () => _doc.RotateFlip(RotateFlipKind.FlipHorizontal)));
        menu.Items.Add(MenuItemFor("Flip Vertical", () => _doc.RotateFlip(RotateFlipKind.FlipVertical)));
        menu.Items.Add(new Separator());
        menu.Items.Add(MenuItemFor("Crop", () => _railButtons[ToolKind.Crop].IsChecked = true));
        menu.Items.Add(new Separator());
        menu.Items.Add(MenuItemFor("Bring Forward", () => Restack(+1)));
        menu.Items.Add(MenuItemFor("Send Backward", () => Restack(-1)));
        menu.Items.Add(MenuItemFor("Delete", DeleteSelection));
        menu.Opened += (_, _) =>
        {
            bool sel = Canvas.Selected is not null;
            for (int i = 6; i < menu.Items.Count; i++)
                if (menu.Items[i] is MenuItem mi) mi.IsEnabled = sel;
        };
        Canvas.ContextMenu = menu;
    }

    private static MenuItem MenuItemFor(string header, Action action)
    {
        var mi = new MenuItem { Header = header };
        mi.Click += (_, _) => action();
        return mi;
    }

    // ============================ tool switching ==================================

    private ToolKind _tool = ToolKind.Arrow;

    private void OnToolSelected(ToolKind kind)
    {
        CommitTextEdit();

        if (kind == ToolKind.Crop)
        {
            EnterCrop();
            return;
        }
        if (Canvas.CropMode) ExitCrop(apply: false);

        if (kind == ToolKind.Image)
        {
            InsertImage();
            _railButtons[ToolKind.Select].IsChecked = true;
            return;
        }

        _tool = kind;
        Canvas.SetTool(kind);
        ToolIconHost.Content = ToolIcons.Create(kind);
        ToolNameLabel.Text = ToolIcons.RailOrder.First(t => t.Kind == kind).Name;

        if (App.Settings.RememberLastTool)
        {
            App.Settings.LastTool = kind.ToString();
            SettingsStore.Save(App.Settings);
        }
        UpdateToolOptions();
    }

    /// <summary>Shows only the option groups relevant to the active tool (contextual top bar).</summary>
    private void UpdateToolOptions()
    {
        bool color = _tool is ToolKind.Arrow or ToolKind.Text or ToolKind.Rectangle or ToolKind.Ellipse
            or ToolKind.Line or ToolKind.Highlight or ToolKind.Pen or ToolKind.Stamp;
        bool width = _tool is ToolKind.Arrow or ToolKind.Rectangle or ToolKind.Ellipse
            or ToolKind.Line or ToolKind.Highlight or ToolKind.Pen;

        SwatchPanel.Visibility = Vis(color);
        SwatchDivider.Visibility = Vis(color || width);
        WidthPanel.Visibility = Vis(width);
        ArrowPanel.Visibility = Vis(_tool == ToolKind.Arrow);
        TextPanel.Visibility = Vis(_tool == ToolKind.Text);
        FillPanel.Visibility = Vis(_tool is ToolKind.Rectangle or ToolKind.Ellipse);
        ObscurePanel.Visibility = Vis(_tool == ToolKind.Obscure);
        StampPanel.Visibility = Vis(_tool == ToolKind.Stamp);
        StickerPanel.Visibility = Vis(_tool == ToolKind.Sticker);
        SpotlightHintPanel.Visibility = Vis(_tool == ToolKind.Spotlight);

        SyncOptionStates();
    }

    private static Visibility Vis(bool v) => v ? Visibility.Visible : Visibility.Collapsed;

    private void SyncOptionStates()
    {
        ArrowTapered.IsChecked = _arrowStyle == ArrowStyle.Tapered;
        ArrowFilled.IsChecked = _arrowStyle == ArrowStyle.Filled;
        ArrowOpen.IsChecked = _arrowStyle == ArrowStyle.Open;
        ArrowConcave.IsChecked = _arrowStyle == ArrowStyle.Concave;
        ArrowDouble.IsChecked = _arrowDouble;
        OutlineToggle.IsChecked = !_shapeFilled;
        FilledToggle.IsChecked = _shapeFilled;
        ObPixelate.IsChecked = _obscureStyle == ObscureStyle.Pixelate;
        ObBlur.IsChecked = _obscureStyle == ObscureStyle.Blur;
        ObBlock.IsChecked = _obscureStyle == ObscureStyle.Block;
        ObStripes.IsChecked = _obscureStyle == ObscureStyle.Stripes;
        StampCheck.IsChecked = _stampKind == StampKind.Check;
        StampCross.IsChecked = _stampKind == StampKind.Cross;
        StampStar.IsChecked = _stampKind == StampKind.Star;
        StampDot.IsChecked = _stampKind == StampKind.Dot;
        StampNumber.IsChecked = _stampKind == StampKind.Number;
        EmojiButton.Content = _emoji;
        PxField.Text = ((int)Math.Round(CurrentWidth)).ToString();
        foreach (var tb in _widthButtons)
            tb.IsChecked = Math.Abs((double)tb.Tag - CurrentWidth) < 0.5;
        ColorWell.Fill = new SolidColorBrush(_color);
    }

    // ---- style setters (also restyle the current selection, v1.4.1 behavior) --------

    private void SetColor(Color c)
    {
        _color = c;
        App.Settings.DefaultColor = c.ToString();
        SettingsStore.Save(App.Settings);
        ApplyToSelected(a => a.Color = c);
        if (_editing is not null) EditBox.Foreground = new SolidColorBrush(c);
        SyncOptionStates();
    }

    private double CurrentWidth
    {
        get => _tool switch
        {
            ToolKind.Arrow => App.Settings.ArrowWidth,
            ToolKind.Highlight => App.Settings.HighlightWidth,
            ToolKind.Pen => App.Settings.PenWidth,
            _ => App.Settings.ShapeWidth,
        };
        set
        {
            switch (_tool)
            {
                case ToolKind.Arrow: App.Settings.ArrowWidth = value; break;
                case ToolKind.Highlight: App.Settings.HighlightWidth = value; break;
                case ToolKind.Pen: App.Settings.PenWidth = value; break;
                default: App.Settings.ShapeWidth = value; break;
            }
            SettingsStore.Save(App.Settings);
        }
    }

    private void SetWidth(double value)
    {
        CurrentWidth = Math.Clamp(value, 1, 200);
        ApplyToSelected(a => a.StrokeWidth = CurrentWidth);
        SyncOptionStates();
    }

    private void CommitPxField()
    {
        if (double.TryParse(PxField.Text, out var v)) SetWidth(v);
        else SyncOptionStates();
    }

    private void SetArrowStyle(ArrowStyle style)
    {
        _arrowStyle = style;
        ApplyToSelected(a => { if (a is ArrowAnnotation ar) ar.Style = style; });
        SyncOptionStates();
    }

    private void SetFilled(bool filled)
    {
        _shapeFilled = filled;
        ApplyToSelected(a => { if (a is BoxAnnotation bx) bx.Filled = filled; });
        SyncOptionStates();
    }

    private void SetObscure(ObscureStyle style)
    {
        _obscureStyle = style;
        App.Settings.ObscureStyle = style.ToString();
        SettingsStore.Save(App.Settings);
        ApplyToSelected(a => { if (a is ObscureAnnotation ob) ob.Style = style; });
        SyncOptionStates();
    }

    private void SetStamp(StampKind kind)
    {
        _stampKind = kind;
        SyncOptionStates();
    }

    private void ApplyToSelected(Action<Annotation> change)
    {
        if (Canvas.Selected is not { } sel) return;
        _doc.PushUndo();
        change(sel);
        _doc.Dirty = true;
        _doc.NotifyChanged();
    }

    /// <summary>Selecting an annotation surfaces its style in the top bar (v1.4.1 parity for text).</summary>
    private void OnSelectionChanged()
    {
        if (Canvas.Selected is TextAnnotation t)
        {
            TextPanel.Visibility = Visibility.Visible;
            SyncTextBar(t);
        }
        else if (_tool != ToolKind.Text)
        {
            TextPanel.Visibility = Visibility.Collapsed;
        }
    }

    /// <summary>Reflect a text annotation's style in the bar WITHOUT firing the change handlers.</summary>
    private void SyncTextBar(TextAnnotation t)
    {
        _syncingSelection = true;
        try
        {
            FontCombo.SelectedItem = Fonts.SystemFontFamilies.Any(f => f.Source == t.FontFamily)
                ? t.FontFamily : FontCombo.SelectedItem;
            FontSizeCombo.Text = t.FontSize.ToString();
            BoldToggle.IsChecked = t.Bold;
            ItalicToggle.IsChecked = t.Italic;
            _fontFamily = t.FontFamily;
            _fontSize = t.FontSize;
            _bold = t.Bold;
            _italic = t.Italic;
        }
        finally
        {
            _syncingSelection = false;
        }
    }

    // ============================ annotation creation ============================

    internal Annotation? MakeDraft(ToolKind tool, Point docPt)
    {
        Annotation? a = tool switch
        {
            ToolKind.Arrow => new ArrowAnnotation
            { Style = _arrowStyle, DoubleHeaded = _arrowDouble, StrokeWidth = App.Settings.ArrowWidth },
            ToolKind.Line => new LineAnnotation { StrokeWidth = App.Settings.ShapeWidth },
            ToolKind.Rectangle => new BoxAnnotation { Filled = _shapeFilled, StrokeWidth = App.Settings.ShapeWidth },
            ToolKind.Ellipse => new BoxAnnotation { IsEllipse = true, Filled = _shapeFilled, StrokeWidth = App.Settings.ShapeWidth },
            ToolKind.Obscure => new ObscureAnnotation { Style = _obscureStyle },
            ToolKind.Spotlight => new SpotlightAnnotation(),
            ToolKind.Pen => new PenAnnotation { StrokeWidth = App.Settings.PenWidth },
            ToolKind.Highlight => new HighlightAnnotation
            {
                StrokeWidth = App.Settings.HighlightWidth,
                Color = _color == ParseColor("#FF3366", "#FF3366") ? ParseColor("#FFD60A", "#FFD60A") : _color,
            },
            _ => null,
        };
        if (a is null) return null;
        if (tool != ToolKind.Highlight) a.Color = _color;
        if (a is TwoPointAnnotation tp) { tp.A = docPt; tp.B = docPt; }
        if (a is RectAnnotation ra) { ra.A = docPt; ra.B = docPt; }
        return a;
    }

    internal void PlaceStamp(Point docPt)
    {
        var stamp = new StampAnnotation
        {
            Kind = _stampKind,
            Center = docPt,
            Color = _color,
            Number = _doc.NextStampNumber,
        };
        _doc.Add(stamp);
        if (_stampKind == StampKind.Number) _doc.NextStampNumber++;
        Canvas.InvalidateVisual();
    }

    internal void PlaceSticker(Point docPt)
    {
        _doc.Add(new StickerAnnotation { Emoji = _emoji, Center = docPt });
        Canvas.InvalidateVisual();
    }

    private void InsertImage()
    {
        var dlg = new Microsoft.Win32.OpenFileDialog
        { Filter = "Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff" };
        if (dlg.ShowDialog(this) != true) return;
        try
        {
            var img = new BitmapImage();
            img.BeginInit();
            img.CacheOption = BitmapCacheOption.OnLoad;
            img.UriSource = new Uri(dlg.FileName);
            img.EndInit();
            img.Freeze();

            var view = _doc.ViewRect;
            double scale = Math.Min(1, Math.Min(view.Width * 0.5 / img.PixelWidth, view.Height * 0.5 / img.PixelHeight));
            double w = img.PixelWidth * scale, h = img.PixelHeight * scale;
            double cx = view.X + view.Width / 2.0, cy = view.Y + view.Height / 2.0;
            var ann = new ImageAnnotation
            {
                Source = img,
                A = new Point(cx - w / 2, cy - h / 2),
                B = new Point(cx + w / 2, cy + h / 2),
            };
            _doc.Add(ann);
            Canvas.Select(ann);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"Couldn't insert image.\n{ex.Message}", "WinSitch");
        }
    }

    // ============================ text editing ===================================

    internal void HandleTextToolClick(Point docPt)
    {
        // Clicking an existing text with the Text tool edits it instead of stacking a new one (v1.4.1).
        var existing = _doc.Annotations.OfType<TextAnnotation>().LastOrDefault(t => t.HitTest(docPt));
        if (existing is not null)
        {
            BeginTextEdit(existing, isNew: false);
            return;
        }
        var t = new TextAnnotation
        {
            Position = docPt,
            Color = _color,
            FontFamily = _fontFamily,
            FontSize = _fontSize,
            Bold = _bold,
            Italic = _italic,
        };
        BeginTextEdit(t, isNew: true);
    }

    internal void BeginTextEdit(TextAnnotation t, bool isNew)
    {
        CommitTextEdit();
        _editing = t;
        _editingIsNew = isNew;
        Canvas.EditingText = t;
        Canvas.Select(null);

        double scale = Canvas.Zoom / _dpi;
        var dip = Canvas.ToDip(t.Position);
        System.Windows.Controls.Canvas.SetLeft(EditBox, dip.X);
        System.Windows.Controls.Canvas.SetTop(EditBox, dip.Y);
        EditBox.FontFamily = new FontFamily(t.FontFamily);
        EditBox.FontSize = t.FontSize * scale;
        EditBox.FontWeight = t.Bold ? FontWeights.Bold : FontWeights.Normal;
        EditBox.FontStyle = t.Italic ? FontStyles.Italic : FontStyles.Normal;
        EditBox.Foreground = new SolidColorBrush(t.Color);
        EditBox.Text = t.Text;
        EditBox.Visibility = Visibility.Visible;
        OverlayLayer.IsHitTestVisible = true;
        Canvas.InvalidateVisual();
        Dispatcher.BeginInvoke(() => { EditBox.Focus(); EditBox.SelectAll(); });

        // Surface this text's style in the bar for restyling without switching tools.
        SyncTextBar(t);
        TextPanel.Visibility = Visibility.Visible;
    }

    internal void CommitTextEdit()
    {
        if (_editing is null) return;
        var t = _editing;
        var text = EditBox.Text.TrimEnd('\r', '\n');
        _editing = null;
        HideEditBox();

        bool kept = false;
        if (_editingIsNew)
        {
            if (!string.IsNullOrWhiteSpace(text))
            {
                t.Text = text;
                _doc.Add(t);
                kept = true;
            }
        }
        else if (text != t.Text)
        {
            _doc.PushUndo();
            if (string.IsNullOrWhiteSpace(text))
            {
                _doc.Annotations.Remove(t);   // clearing removes it — and that's undoable
            }
            else
            {
                t.Text = text;
                kept = true;
            }
            _doc.Dirty = true;
            _doc.NotifyChanged();
        }
        else
        {
            kept = _doc.Annotations.Contains(t);
        }
        Canvas.EditingText = null;
        // Select the committed text so an in-flight toolbar click (which stole focus and
        // triggered this commit) restyles it instead of vanishing into a no-op.
        if (kept) Canvas.Select(t);
        Canvas.InvalidateVisual();
    }

    private void CancelTextEdit()
    {
        _editing = null;
        Canvas.EditingText = null;
        HideEditBox();
        Canvas.InvalidateVisual();
    }

    private void HideEditBox()
    {
        EditBox.Visibility = Visibility.Collapsed;
        OverlayLayer.IsHitTestVisible = false;
        Keyboard.ClearFocus();
    }

    // ============================ crop ==========================================

    private void EnterCrop()
    {
        CommitTextEdit();
        Canvas.EnterCropMode();
        NormalBar.Visibility = Visibility.Collapsed;
        CropBar.Visibility = Visibility.Visible;
        AspectCombo.SelectedIndex = 0;
        CropAspectRatio = 0;
        LockToggle.IsChecked = false;
        SyncCropFieldsFromDraft();
        FitZoom();
    }

    private void ExitCrop(bool apply)
    {
        if (apply)
        {
            var r = Canvas.CropDraft;
            _doc.ApplyCrop(new Int32Rect(
                (int)Math.Round(r.X), (int)Math.Round(r.Y),
                (int)Math.Round(r.Width), (int)Math.Round(r.Height)));
        }
        Canvas.ExitCropMode();
        CropBar.Visibility = Visibility.Collapsed;
        NormalBar.Visibility = Visibility.Visible;
        var back = _tool is ToolKind.Crop or ToolKind.Image ? ToolKind.Select : _tool;
        _railButtons[back].IsChecked = true;
        Canvas.SetTool(back);
        FitZoom();
        UpdateBottom();
    }

    private void SyncCropFieldsFromDraft()
    {
        _syncingCrop = true;
        CropW.Text = ((int)Math.Round(Canvas.CropDraft.Width)).ToString();
        CropH.Text = ((int)Math.Round(Canvas.CropDraft.Height)).ToString();
        _syncingCrop = false;
    }

    private void CropFieldEdited(bool widthEdited)
    {
        if (_syncingCrop || !Canvas.CropMode) return;
        if (!int.TryParse(CropW.Text, out int w) || !int.TryParse(CropH.Text, out int h)) return;
        w = Math.Clamp(w, 1, _doc.Width);
        h = Math.Clamp(h, 1, _doc.Height);

        // Honor an active aspect lock/preset: the edited field drives the other.
        if (CropAspectRatio > 0)
        {
            if (widthEdited) h = Math.Max(1, (int)Math.Round(w / CropAspectRatio));
            else w = Math.Max(1, (int)Math.Round(h * CropAspectRatio));
            if (w > _doc.Width) { w = _doc.Width; h = Math.Max(1, (int)Math.Round(w / CropAspectRatio)); }
            if (h > _doc.Height) { h = _doc.Height; w = Math.Max(1, (int)Math.Round(h * CropAspectRatio)); }
            _syncingCrop = true;
            if (widthEdited) CropH.Text = h.ToString(); else CropW.Text = w.ToString();
            _syncingCrop = false;
        }

        var r = Canvas.CropDraft;
        r.Width = w;
        r.Height = h;
        r.X = Math.Clamp(r.X, 0, _doc.Width - w);
        r.Y = Math.Clamp(r.Y, 0, _doc.Height - h);
        Canvas.SetCropDraft(r);
    }

    private void UpdateLock()
    {
        if (LockToggle.IsChecked == true)
        {
            _lockedRatio = Canvas.CropDraft.Width / Math.Max(1, Canvas.CropDraft.Height);
            if (CropAspectRatio <= 0) CropAspectRatio = _lockedRatio;
        }
        else if (AspectCombo.SelectedIndex == 0)
        {
            CropAspectRatio = 0;
        }
    }

    private void ReshapeCropToRatio(double ratio)
    {
        var r = Canvas.CropDraft;
        double cx = r.X + r.Width / 2, cy = r.Y + r.Height / 2;
        double w = r.Width, h = w / ratio;
        if (h > _doc.Height) { h = _doc.Height; w = h * ratio; }
        if (w > _doc.Width) { w = _doc.Width; h = w / ratio; }
        var nr = new Rect(cx - w / 2, cy - h / 2, w, h);
        nr.X = Math.Clamp(nr.X, 0, _doc.Width - w);
        nr.Y = Math.Clamp(nr.Y, 0, _doc.Height - h);
        Canvas.SetCropDraft(nr);
        SyncCropFieldsFromDraft();
    }

    // ============================ zoom ==========================================

    internal void NudgeZoom(double factor) => Canvas.SetZoom(Canvas.Zoom * factor);

    private void FitZoom()
    {
        var v = Canvas.CropMode ? new Int32Rect(0, 0, _doc.Width, _doc.Height) : _doc.ViewRect;
        double availW = Math.Max(80, Scroller.ViewportWidth - 40) * _dpi;
        double availH = Math.Max(80, Scroller.ViewportHeight - 40) * _dpi;
        if (Scroller.ViewportWidth < 1)
        {
            availW = Math.Max(80, (ActualWidth - 46 - 60)) * _dpi;
            availH = Math.Max(80, (ActualHeight - 44 - 40 - 80)) * _dpi;
        }
        Canvas.SetZoom(Math.Min(1.0, Math.Min(availW / v.Width, availH / v.Height)));
    }

    internal void OnZoomChanged()
    {
        if (ZoomText is not null)
            ZoomText.Text = $"{Math.Round(Canvas.Zoom * 100)}%";
        // The EditBox overlay is positioned/scaled for one specific zoom — end the session
        // rather than leave it floating at a stale position.
        if (_editing is not null) CommitTextEdit();
    }

    private void ShowZoomMenu()
    {
        var menu = new ContextMenu();
        menu.Items.Add(MenuItemFor("Fit", FitZoom));
        foreach (var pct in new[] { 25, 50, 75, 100, 150, 200, 300 })
            menu.Items.Add(MenuItemFor($"{pct}%", () => Canvas.SetZoom(pct / 100.0)));
        menu.PlacementTarget = BtnZoomLabel;
        menu.IsOpen = true;
    }

    // ============================ output actions ==================================

    private BitmapSource RenderFinal() => Renderer.RenderToBitmap(_doc);

    private void CopyImage()
    {
        CommitTextEdit();
        if (ClipboardHelper.CopyImage(RenderFinal()))
            NotifyPopup.Show("Copied to clipboard.");
        else
            NotifyPopup.Show("Clipboard is busy — try again.");
    }

    private void ShowSaveMenu()
    {
        var menu = new ContextMenu();
        foreach (var fmt in Exporters.Formats)
        {
            var mi = new MenuItem { Header = "." + fmt, IsCheckable = true, IsChecked = fmt == _saveFormat };
            var f = fmt;
            mi.Click += (_, _) => { _saveFormat = f; FormatText.Text = "." + f; SaveAs(); };
            menu.Items.Add(mi);
        }
        menu.Items.Add(new Separator());
        menu.Items.Add(MenuItemFor("Save As…", SaveAs));
        menu.PlacementTarget = BtnSave;
        menu.IsOpen = true;
    }

    private void SaveAs()
    {
        CommitTextEdit();
        var dlg = new Microsoft.Win32.SaveFileDialog
        {
            FileName = _docName,
            DefaultExt = "." + _saveFormat,
            Filter = "PNG|*.png|JPEG|*.jpg|PDF|*.pdf|TIFF|*.tiff",
            FilterIndex = Array.IndexOf(Exporters.Formats, _saveFormat) + 1,
            InitialDirectory = Directory.Exists(App.Settings.DefaultSaveFolder) ? App.Settings.DefaultSaveFolder : null,
        };
        if (dlg.ShowDialog(this) != true) return;
        try
        {
            Exporters.Save(RenderFinal(), dlg.FileName);
            _doc.Dirty = false;
            NotifyPopup.Show($"Saved {IOPath.GetFileName(dlg.FileName)}");
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"Save failed.\n{ex.Message}", "WinSitch",
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void ShareImage()
    {
        CommitTextEdit();
        var hwnd = new System.Windows.Interop.WindowInteropHelper(this).Handle;
        ShareHelper.TryShare(hwnd, RenderFinal(), _docName, WriteTempPng);
    }

    private void StartDragOut()
    {
        CommitTextEdit();
        try
        {
            var path = WriteTempPng(RenderFinal());
            var data = new DataObject();
            data.SetFileDropList([path]);
            data.SetImage(RenderFinal());
            DragDrop.DoDragDrop(BtnDragOut, data, DragDropEffects.Copy);
        }
        catch { /* drag aborted */ }
    }

    private string WriteTempPng(BitmapSource bmp)
    {
        var dir = IOPath.Combine(IOPath.GetTempPath(), "WinSitch");
        Directory.CreateDirectory(dir);
        var path = IOPath.Combine(dir, SafeFileName($"{_docName} {DateTime.Now:HH.mm.ss}.png"));
        Exporters.Save(bmp, path);
        _tempFiles.Add(path);
        return path;
    }

    private static string SafeFileName(string name) =>
        string.Concat(name.Select(c => IOPath.GetInvalidFileNameChars().Contains(c) ? '_' : c));

    private void CleanupTempFiles()
    {
        foreach (var f in _tempFiles)
            try { File.Delete(f); } catch { }
    }

    // ============================ misc =============================================

    private void TrashClicked()
    {
        CommitTextEdit();
        if (Canvas.Selected is not null)
        {
            DeleteSelection();
            return;
        }
        if (_doc.Annotations.Count == 0) return;
        if (MessageBox.Show(this, "Remove all annotations?", "WinSitch",
                MessageBoxButton.OKCancel, MessageBoxImage.Question) == MessageBoxResult.OK)
        {
            _doc.PushUndo();
            _doc.Annotations.Clear();
            _doc.Dirty = true;
            _doc.NotifyChanged();
        }
    }

    private void DeleteSelection()
    {
        if (Canvas.Selected is not { } sel) return;
        _doc.Remove(sel);
        Canvas.Select(null);
    }

    private void Restack(int direction)
    {
        if (Canvas.Selected is not { } sel) return;
        int i = _doc.Annotations.IndexOf(sel);
        int j = i + direction;
        if (i < 0 || j < 0 || j >= _doc.Annotations.Count) return;
        _doc.PushUndo();
        (_doc.Annotations[i], _doc.Annotations[j]) = (_doc.Annotations[j], _doc.Annotations[i]);
        _doc.Dirty = true;
        _doc.NotifyChanged();
    }

    private void OnDocChanged()
    {
        // Undo/redo restores clones — drop a selection that points at a detached ghost.
        if (Canvas.Selected is { } sel && !_doc.Annotations.Contains(sel))
            Canvas.Select(null);
        Canvas.InvalidateMeasure();
        Canvas.InvalidateVisual();
        UpdateBottom();
    }

    private void UpdateBottom()
    {
        BtnUndo.IsEnabled = _doc.CanUndo;
        BtnRedo.IsEnabled = _doc.CanRedo;
        var v = _doc.ViewRect;
        SizeReadout.Text = $"{v.Width} × {v.Height} px";
        OnZoomChanged();
    }

    private void OnPreviewKey(object sender, KeyEventArgs e)
    {
        bool ctrl = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        bool shift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);

        if (_editing is not null) return; // EditBox handles its own keys

        if (Canvas.CropMode)
        {
            if (e.Key == Key.Escape) { ExitCrop(apply: false); e.Handled = true; return; }
            if (e.Key == Key.Enter) { ExitCrop(apply: true); e.Handled = true; return; }
        }

        switch (e.Key)
        {
            case Key.Escape:
                if (Canvas.Selected is not null) Canvas.Select(null);
                e.Handled = true;
                break;
            case Key.Delete or Key.Back when Canvas.Selected is not null
                && Keyboard.FocusedElement is not TextBox:
                DeleteSelection();
                e.Handled = true;
                break;
            // Never hijack undo/redo from a focused TextBox (px field, crop W/H, …).
            case Key.Z when ctrl && shift && Keyboard.FocusedElement is not TextBox:
            case Key.Y when ctrl && Keyboard.FocusedElement is not TextBox:
                _doc.Redo();
                e.Handled = true;
                break;
            case Key.Z when ctrl && Keyboard.FocusedElement is not TextBox:
                _doc.Undo();
                e.Handled = true;
                break;
            case Key.C when ctrl && Keyboard.FocusedElement is not TextBox:
                CopyImage();
                e.Handled = true;
                break;
            case Key.S when ctrl:
                SaveAs();
                e.Handled = true;
                break;
            case Key.D0 when ctrl:
                Canvas.SetZoom(1.0);
                e.Handled = true;
                break;
            case Key.OemPlus or Key.Add when ctrl:
                NudgeZoom(1.25);
                e.Handled = true;
                break;
            case Key.OemMinus or Key.Subtract when ctrl:
                NudgeZoom(1 / 1.25);
                e.Handled = true;
                break;
        }
    }

    // ---- close / save prompt ---------------------------------------------------------

    public bool ConfirmClose()
    {
        CommitTextEdit();
        // Crop/rotate/flip count as changes too; a fully undone doc counts as pristine.
        bool pristine = _doc.Annotations.Count == 0 && _doc.Crop is null && _doc.BaseVersion == 0;
        if (!_doc.Dirty || pristine) return true;
        var result = MessageBox.Show(this,
            "You have unsaved changes. Save before closing?",
            "WinSitch", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
        switch (result)
        {
            case MessageBoxResult.Yes:
                SaveAs();
                return !_doc.Dirty;
            case MessageBoxResult.No:
                return true;
            default:
                return false;
        }
    }

    private void OnClosingPrompt(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        if (!_closeConfirmed)
        {
            if (!ConfirmClose()) { e.Cancel = true; return; }
            _closeConfirmed = true;
        }
        RememberWindowSize();
    }

    /// <summary>The next editor opens with the dimensions this one closes with.</summary>
    private void RememberWindowSize()
    {
        if (WindowState == WindowState.Maximized)
        {
            App.Settings.EditorMaximized = true;
            if (RestoreBounds.Width >= MinWidth && RestoreBounds.Height >= MinHeight)
            {
                App.Settings.EditorWidth = RestoreBounds.Width;
                App.Settings.EditorHeight = RestoreBounds.Height;
            }
        }
        else if (WindowState == WindowState.Normal && ActualWidth >= MinWidth && ActualHeight >= MinHeight)
        {
            App.Settings.EditorMaximized = false;
            App.Settings.EditorWidth = ActualWidth;
            App.Settings.EditorHeight = ActualHeight;
        }
        SettingsStore.Save(App.Settings);
    }

    /// <summary>Close after the caller already ran ConfirmClose (avoids double prompts on Quit).</summary>
    public void CloseWithoutPrompt()
    {
        _closeConfirmed = true;
        Close();
    }

    // ---- pickers -----------------------------------------------------------------

    private void ShowColorPicker(UIElement target)
    {
        var popup = new Popup
        {
            PlacementTarget = target,
            Placement = PlacementMode.Bottom,
            StaysOpen = false,
            AllowsTransparency = true,
        };
        var grid = new UniformGrid { Columns = 8, Margin = new Thickness(6) };
        string[] extra =
        [
            "#FF3366", "#FF2D55", "#FF6482", "#FF9500", "#FFB340", "#FFD60A", "#FFE566", "#FFFFFF",
            "#34C759", "#63D97F", "#0A8F3C", "#2E7DF6", "#66A3F8", "#0A4FB5", "#5E5CE6", "#8482EC",
            "#AF52DE", "#C47FE8", "#7A1FA6", "#FF3B30", "#B22219", "#8E8E93", "#48484C", "#1D1D1F",
        ];
        foreach (var hex in extra)
        {
            var c = ParseColor(hex, "#FF3366");
            var b = new Button
            {
                Width = 26, Height = 26, Margin = new Thickness(2),
                Style = (Style)FindResource("IconButton"),
                Content = new Ellipse
                {
                    Width = 18, Height = 18, Fill = new SolidColorBrush(c),
                    Stroke = new SolidColorBrush(Color.FromArgb(0x55, 0x80, 0x80, 0x88)), StrokeThickness = 1,
                },
                ToolTip = hex,
            };
            b.Click += (_, _) => { SetColor(c); popup.IsOpen = false; };
            grid.Children.Add(b);
        }

        var hexBox = new TextBox
        {
            Style = (Style)FindResource("Field"),
            Text = _color.ToString(),
            Margin = new Thickness(8, 2, 8, 8),
        };
        hexBox.KeyDown += (_, e) =>
        {
            if (e.Key != Key.Enter) return;
            try
            {
                SetColor((Color)ColorConverter.ConvertFromString(hexBox.Text.Trim()));
                popup.IsOpen = false;
            }
            catch { /* invalid hex — leave open */ }
        };

        var panel = new StackPanel();
        panel.Children.Add(grid);
        panel.Children.Add(hexBox);
        popup.Child = new Border
        {
            Background = (Brush)FindResource("Brush.Title"),
            BorderBrush = (Brush)FindResource("Brush.Divider"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(10),
            Child = panel,
        };
        popup.IsOpen = true;
    }

    private void ShowEmojiPicker()
    {
        var popup = new Popup
        {
            PlacementTarget = EmojiButton,
            Placement = PlacementMode.Bottom,
            StaysOpen = false,
            AllowsTransparency = true,
        };
        string[] emoji =
        [
            "😀", "😅", "😂", "😊", "😍", "🤔", "😎", "😮",
            "😢", "😡", "🙃", "🤯", "👍", "👎", "👏", "🙏",
            "💪", "👀", "🔥", "⭐", "✨", "🎉", "❤️", "💡",
            "⚠️", "❌", "✅", "❓", "❗", "🚀", "🐛", "🔒",
        ];
        var grid = new UniformGrid { Columns = 8, Margin = new Thickness(6) };
        foreach (var e in emoji)
        {
            var b = new Button
            {
                Content = e, FontSize = 17, Width = 32, Height = 32,
                Style = (Style)FindResource("IconButton"),
            };
            var chosen = e;
            b.Click += (_, _) =>
            {
                _emoji = chosen;
                EmojiButton.Content = chosen;
                popup.IsOpen = false;
            };
            grid.Children.Add(b);
        }
        popup.Child = new Border
        {
            Background = (Brush)FindResource("Brush.Title"),
            BorderBrush = (Brush)FindResource("Brush.Divider"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(10),
            Child = grid,
        };
        popup.IsOpen = true;
    }

    private static Color ParseColor(string hex, string fallback)
    {
        try { return (Color)ColorConverter.ConvertFromString(hex); }
        catch { return (Color)ColorConverter.ConvertFromString(fallback); }
    }

    /// <summary>Pre-places showcase annotations for `--demo` (README screenshots, smoke tests).</summary>
    internal void SetUpDemoAnnotations(bool cropMode)
    {
        var pink = ParseColor("#FF3366", "#FF3366");
        var yellow = ParseColor("#FFD60A", "#FFD60A");

        _doc.Annotations.Add(new BoxAnnotation
        { A = new Point(78, 182), B = new Point(410, 340), Color = pink, StrokeWidth = 9 });
        _doc.Annotations.Add(new HighlightAnnotation
        {
            Color = yellow, StrokeWidth = 40,
            Points = [new Point(102, 528), new Point(770, 528)],
        });
        _doc.Annotations.Add(new ObscureAnnotation
        { A = new Point(1185, 500), B = new Point(1402, 660), Style = ObscureStyle.Pixelate });
        _doc.Annotations.Add(new ArrowAnnotation
        { A = new Point(760, 128), B = new Point(430, 240), Color = pink, StrokeWidth = 20 });
        _doc.Annotations.Add(new TextAnnotation
        {
            Position = new Point(778, 106), Text = "Best growth in Q3!", Color = pink,
            FontSize = 40, Bold = true,
        });
        _doc.Annotations.Add(new StampAnnotation
        { Kind = StampKind.Check, Center = new Point(1330, 300), Color = ParseColor("#34C759", "#34C759"), Size = 52 });

        _doc.Dirty = false;
        _doc.NotifyChanged();
        if (cropMode) _railButtons[ToolKind.Crop].IsChecked = true;
    }
}
