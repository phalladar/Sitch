# Sitch — Architecture

Deep reference for how the code is organized and the invariants it deliberately upholds. Read
this before changing capture/DPI, the annotation/render pipeline, or clipboard/share. For *what*
we build see [SPEC.md](SPEC.md); for the stack/decision rationale see [PLAN.md](PLAN.md).

Citations use `File.cs` + the class/method name (not line numbers) so they survive edits.

## The cardinal rule: two coordinate spaces, never mixed

- **Capture (`Capture/`) is physical virtual-screen pixels.** The desktop is frozen once with a
  GDI `BitBlt(SRCCOPY|CAPTUREBLT)` of the whole virtual screen (`ScreenFreezer`), and one
  borderless topmost overlay is shown **per monitor** (`OverlayWindow`), each placed by physical
  `SetWindowPos` — bypassing WPF's DIP layout. All selection state lives in `CaptureController`
  in physical coords, so a drag can span monitors with different scale factors and stay exact.
  Each overlay converts local DIP ↔ physical using its own monitor scale (`OverlayWindow.ToPhysical`).
- **Document/editor (`Core/`, `Editor/`) is document pixels.** `DocumentCanvas` renders at
  `Zoom` = *physical screen px per document px*, converting to DIP only for on-screen layout
  (`ToDoc`/`ToDip`). So 100% zoom is pixel-perfect at any monitor scale.
- This physical-pixel discipline is the entire reason mixed-DPI multi-monitor capture is correct
  (the ShareX bug graveyard — see PLAN.md risk register). Treat changes in `Capture/` as high-risk
  and verify on a mixed-DPI setup.
- The app manifest declares **Per-Monitor-V2** DPI awareness (`app.manifest`), which is what makes
  Win32 coordinates physical and `WM_DPICHANGED` synchronous.

## Data model & render pipeline (`Core/`)

- **`Document`** = an immutable pristine `BitmapSource` + an **ordered** annotation list + an
  optional non-destructive crop. Undo/redo is whole-document **snapshots** (max ~100; simple and
  correct — per-op commands can come later). `RotateFlip` maps annotation coordinates so marks
  follow the image. Raises `Changed`; exposes `Dirty`, `NextStampNumber`.
- **`Annotation`** (abstract) is the base for every mark: color/stroke, `IsEffect`/`IsSpotlight`
  flags, `Render`, `Clone`, `MoveBy`, `ApplyTransform`, hit-test, resize handles. Subclasses:
  - `AnnotationShapes.cs` — `ArrowAnnotation` (the signature tapered/filled/open/concave,
    double-headed geometry), `LineAnnotation`, `BoxAnnotation` (rect/ellipse, outline/filled).
  - `AnnotationMarks.cs` — `TextAnnotation` (system font, bold/italic, contrast halo, re-editable),
    `StampAnnotation` (check/cross/star/dot/auto-number), `StickerAnnotation` (emoji),
    `ImageAnnotation` (image overlay).
  - `AnnotationFreehand.cs` — `PenAnnotation`, `HighlightAnnotation` (multiply-ish wash).
  - `AnnotationEffects.cs` — `ObscureAnnotation` (pixelate/blur/block/stripes; cached, keyed on
    `BaseVersion`) + `SpotlightAnnotation`; raw-pixel `EffectRenderer` operates on the full-res base.
- **`Renderer`** is the single composition pipeline shared by canvas preview and export:
  `base → obscure effects → spotlight dim → vector marks`. **Effects flatten BEFORE vector
  shapes**, so blur/pixelate never smears an arrow. `RenderToBitmap` applies the crop and
  flattens at full resolution — this is the only place redactions become destructive pixels.
  Prefer solid block / stripes for real secrets (opaque ink; blur/pixelate are filters).

## Module map (`windows/Sitch/`)

Namespaces mirror folders. Root: `App.xaml`/`App.xaml.cs` (entry point, arg + IPC routing,
capture orchestration, window management), `app.manifest` (PMv2), `Sitch.csproj`.

- **`Capture/`** — freeze-frame engine. `Native.cs` (hand-written Win32/GDI/DWM/DPI P/Invoke),
  `MonitorInfoProvider` (`MonitorData`, physical bounds + DPI, primary-first ordering),
  `ScreenFreezer` (BitBlt grab + `Crop`), `WindowEnumerator` (`WindowEntry`, alt-tab list via
  DWM extended-frame bounds; `CaptureWindow` uses `PrintWindow(PW_RENDERFULLCONTENT)` and bails to
  a frozen-crop on DPI mismatch), `CaptureController` (interactive + non-interactive capture),
  `OverlayWindow` (per-monitor overlay + nested `OverlayVisual` painter).
- **`Core/`** — see above, plus `AppSettings.cs` (`PixelRect`, `AppSettings`, `SettingsStore`) and
  `HotkeyChord.cs` (parse/format "Ctrl+Alt+4" ↔ native modifiers/vkey).
- **`Editor/`** — `EditorWindow.xaml(.cs)` (multi-tab editor; rail/top/bottom bars, tool switching,
  draft creation, in-place text edit, crop mode, zoom, copy/save/share/drag-out, save prompts),
  `DocumentCanvas.cs` (the annotation canvas; hit-testing, handles, crop chrome),
  `SettingsWindow.xaml(.cs)` (3-tab settings + hotkey recorder), `ToolIcons.cs` (`ToolKind` enum =
  canonical 14-tool order + vector glyphs + `RailOrder`), `DemoMode.cs` (`--demo*` + `--shot-region`).
- **`Export/`** — `Exporters.cs` (`Formats = [png,jpg,pdf,tiff]`, `Save`, `QuickSave`),
  `ClipboardHelper.cs` (PNG + CF_BITMAP-on-white, retry loop), `ShareHelper.cs` (Windows Share sheet).
- **`Shell/`** — `TrayController.cs` (tray icon/menu + About dialog), `HotkeyManager.cs`
  (`RegisterHotKey` on a message-only HwndSource, MOD_NOREPEAT), `SingleInstance.cs` (mutex + pipe),
  `ScreenshotWatcher.cs` (FileSystemWatcher on `Pictures\Screenshots`), `StartupManager.cs`
  (HKCU Run + StartupApproved), `ThemeManager.cs` (swap active theme dictionary), `WelcomeWindow.cs`
  (first-run, code-built), `NotifyPopup.cs` (self-drawn toast), `CountdownPopup.cs` (timer overlay).
- **`Themes/`** — `Common.xaml` (theme-independent styles/templates), `Dark.xaml`, `Light.xaml`
  (brush palettes). `App.xaml` merges the active theme at `MergedDictionaries[0]` (the swappable
  slot) + `Common.xaml` at `[1]`.
- **`Assets/`** — `sitch.ico` (app/tray/window icon).

## Capture flow

- **One hotkey covers region + window.** In Region mode a drag captures a region, but a plain
  click (no drag) captures the hovered window (`CaptureController.EndDrag`; hover highlight in
  `OverlayWindow`). Window mode always captures the hovered window.
- **Keyboard capture:** arrows define/nudge the selection, Shift+arrows resize, Ctrl = 10px steps,
  Enter confirms, **Esc abandons the whole capture** (single press — `OverlayWindow.OnKeyDown` →
  `CaptureController.Cancel`; the overlay under the cursor takes keyboard focus in
  `OnSourceInitialized` so the key always lands). Right-click also cancels.
  *(This single-Esc behavior deviates from SPEC.md's older "three-stage escape" — code wins.)*
- **After a capture, `App.RouteCapture`** applies the configured after-capture actions
  (show editor / copy / save, any combo). `AppSettings.AfterCopy` defaults **true**, so every
  capture lands on the clipboard immediately; a failed copy does NOT count as "handled", so a busy
  clipboard still falls back to opening the editor.

## Editor specifics

- **Multi-tab.** An `EditorWindow` hosts several `DocTab`s; the in-editor "New Capture" button adds
  a tab (`App.CaptureRegionInto`). Tab chrome is hidden for a single capture. Close/quit run
  per-tab dirty prompts. A doc is **pristine** (no save prompt) only when it has zero annotations,
  no crop, and `BaseVersion == 0` — crop/rotate/flip count as changes (`IsPristine`).
- **Sizing/DPI.** The editor opens on the display the capture came from and reads DPI before
  sizing (`OnSourceInit`); thereafter it remembers the last window size.
- **In-place text edit.** The `EditBox` is positioned/scaled for one specific zoom, so any
  zoom/DPI change commits the edit (`OnZoomChanged`/`OnDpiChanged`). Focus moving into the font
  controls mid-edit is a restyle, not a commit (`IsWithinFontControls`).
- **Undo/redo restores clones**, so a live selection pointing at a now-detached object is dropped
  (`OnDocChanged`).

## WPF / interop pitfalls (already flagged in comments)

- Paint overlays in a **child `FrameworkElement`**, not `Window.OnRender` — the Window template
  paints its Background over `OnRender` (`OverlayWindow`/`OverlayVisual`).
- Clipboard: write PNG + `CF_DIB` flattened on white + `CF_BITMAP` together and **retry on
  `CLIPBRD_E_CANT_OPEN`** (another app may briefly hold the clipboard) — `ClipboardHelper`.
- Share: the handler **must never throw** (the OS can kill the process on a failed return); keep
  the manager rooted per window — `ShareHelper`.
- PDF page size = pixels × 72/96; never trust an embedded bitmap DPI — `Exporters`.
- `--shot-region=<path>` runs a headless render-and-exit **before** acquiring the single-instance
  mutex, so it never disturbs a running instance (`App.OnStartup`).

## Persistence

Mutate the static `App.Settings` (an `AppSettings`), then call `SettingsStore.Save(App.Settings)`.
`SettingsStore` writes indented JSON to `%APPDATA%\Sitch\settings.json` via a `.tmp` +
`File.Move(overwrite)` atomic swap; `Load()` returns defaults on a missing/corrupt file and sets
`FirstRun`. All persistence is best-effort (exceptions swallowed).

**Rebrand migration (WinSitch → Sitch, 0.2.0).** If the new settings file is missing, `Load()`
first *copies* `%APPDATA%\WinSitch\settings.json` across (copy, so a still-running old exe isn't
broken). `StartupManager.MigrateLegacy()` replaces a `WinSitch` HKCU Run entry with a `Sitch` one,
preserving its Task-Manager enabled/disabled state. Mutex/pipe names changed, so an old WinSitch
and a new Sitch can run side by side — the second to start loses the hotkey registration.

## macOS port (`mac/`)

A translation, not shared code: `windows/Sitch` is the reference implementation, and every
invariant above holds on the Mac too. Same module names; differences that matter:

- **`SitchCore` (library, `swift test`)** — the document model, annotations, `Renderer`,
  `EffectRenderer`, settings, `HotkeyChord`, demo document. **Document space is pixels with a
  TOP-LEFT origin**, exactly as on Windows: every CGContext the renderer draws into is flipped
  (`Draw.makeContext`), images go through `Draw.image` (draws upright in a flipped context) and
  text through `TextLayout` (AppKit attributed strings against a flipped `NSGraphicsContext`).
  Annotation code therefore ports line for line from the C#. Pixelate/blur are the same byte
  loops; spotlight dims, then clears the union of the spot rects in a transparency layer.
- **Capture coordinates** — `Capture/` works in **global points, top-left origin at the primary
  display** (Quartz display space, as used by CGWindowList and ScreenCaptureKit). Per-display
  pixels = points × that display's scale; AppKit's bottom-left space appears only at the
  NSWindow/NSEvent boundary. Frames are frozen per display with ScreenCaptureKit
  (`CGDisplayCreateImage`/`CGWindowListCreateImage` are gone on macOS 15). A region is limited
  to the display the drag started on, like macOS's own ⇧⌘4.
- **Zoom** — "device pixels per document pixel", like Windows: points per doc px =
  zoom / `backingScaleFactor`, so 100% is pixel-perfect on Retina too.
- **Point scale** — `Document.pointScale` (2 for a Retina capture, from DPI metadata for opened
  files) makes exports keep their on-screen size: PDF page = px / scale pt, PNG DPI = 72 × scale.
- **Shell** — menu-bar `NSStatusItem` (tray), Carbon `RegisterEventHotKey` (no Accessibility
  prompt), `SMAppService` login item, native window tabs instead of the in-window tab strip,
  distributed notification instead of the named pipe for single-instance arg forwarding.
- **Permission** — Screen Recording (TCC) gates every capture; the grant is tied to the code
  signature, so ad-hoc rebuilds lose it (sign dev builds with the Developer ID).

## License guardrail

ShareX, Greenshot, and Flameshot are GPL — **architecture reference only, never copy or port their
code**. This is a clean-room implementation; reuse only MIT-compatible sources (see PLAN.md).
