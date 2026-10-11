# Sitch (formerly WinSitch) — Build Plan

Goal: a **standalone Windows executable** (no installer, no preinstalled runtime) implementing
`SPEC.md`. This plan encodes the decisions from the July 2026 research pass (18 research topics,
full digest in `research/digest.md`).

---

## 1. Stack decision

**.NET (LTS) + WPF, self-contained single-file publish.**

Why WPF won (ranked evaluation in digest §stack-choice):

1. All four make-or-break capabilities are first-class and battle-proven:
   - transparent/borderless full-screen overlay windows (`AllowsTransparency` + `WS_EX_LAYERED/TRANSPARENT`),
   - Per-Monitor-V2 DPI via app manifest,
   - vector canvas with **in-place editable text** (real `TextBox` on canvas + Adorner framework),
   - deep shell interop (Share sheet, clipboard, drag-drop, tray) with documented .NET recipes.
2. The entire Windows screenshot-tool ecosystem (ShareX, Greenshot) is C#/.NET — richest body of
   reference architecture.
3. Costs accepted: ~60–80 MB compressed single exe; 2–3 s cold start **paid once at login** — the
   app is tray-resident, so the capture path is always warm. Mitigate with ReadyToRun +
   `EnableCompressionInSingleFile`.

Rejected: **Avalonia** (NativeAOT is tempting but click-through overlay + Share interop cost extra
days; revisit only if exe size becomes a hard requirement) · **WinUI 3** (no transparent windows —
disqualifying for an overlay app) · **Qt** (license friction + C++ overhead for a solo dev) ·
**Tauri/Electron** (overlay click-through hacks, mixed-DPI CSS-pixel math, wrong shape for a tray
utility) · **Rust-native** (canvas text editing/IME/a11y immature).

### Project setup

- TFM: `net10.0-windows10.0.19041.0` (LTS; falls back to net8.0 if any dependency lags). CsWinRT
  projections for `Windows.Graphics.Capture` + `DataTransferManager` come free with the TFM.
- `app.manifest`: `<dpiAwareness>PerMonitorV2</dpiAwareness>`.
- Publish profile: `PublishSingleFile` + `SelfContained` + `PublishReadyToRun` +
  `EnableCompressionInSingleFile`, `win-x64` (add `win-arm64` later).
- Packages: `Microsoft.Windows.CsWin32` (P/Invoke source gen) · `H.NotifyIcon.Wpf` (tray) ·
  `PDFsharp-wpf` 6.2.4 (MIT; PDF export via `XImage.FromBitmapSource`, page size in points =
  px·72/DPI) · `Microsoft.Toolkit.Uwp.Notifications` (toasts, unpackaged-OK).
- OS floor: Windows 10 1903+ (WGC window interop); Win11 gets borderless WGC.

## 2. Architecture

```
Sitch.exe
├─ AppShell        tray icon (H.NotifyIcon), single-instance (Global\ mutex + named pipe +
│                  AllowSetForegroundWindow handoff), RegisterHotKey w/ MOD_NOREPEAT,
│                  settings store (JSON, %APPDATA%\Sitch), run-at-login (HKCU Run +
│                  StartupApproved check), toasts
├─ Capture         freeze-frame engine: BitBlt(SRCCOPY|CAPTUREBLT) of entire virtual screen
│                  (physical px under PMv2) → one borderless TopMost overlay window PER MONITOR
│                  drawing its slice; selection math in virtual-screen physical coords.
│                  Window picking: EnumWindows + IsWindowVisible + !DWMWA_CLOAKED +
│                  !WS_EX_TOOLWINDOW, rects from DWMWA_EXTENDED_FRAME_BOUNDS.
│                  Occluded-window capture: WGC CreateForWindow → PrintWindow(PW_RENDERFULLCONTENT)
│                  fallback → frozen-bitmap crop. HDR: v1 SDR BitBlt; v1.x WGC FP16 +
│                  SDR-white-level tone map (the Snipping-Tool-HDR gap).
├─ Document        pristine BitmapSource + ObservableCollection<Annotation> (ordered).
│                  Annotation = vector object w/ typed properties (color, width, style…).
│                  Effect annotations (obscure, spotlight) re-sample the composition beneath
│                  them per frame — non-destructive until export.
│                  Undo: whole-document snapshot stack for v1 → per-op commands with drag-merge later.
├─ EditorView      WPF window per document; left rail / top options bar / bottom bar per SPEC
│                  tokens; canvas = layered Image + annotation ItemsControl + Adorners
│                  (8 handles); crop modal takeover; zoom; precision crosshair cursors;
│                  Light/Dark/System theme dictionaries.
└─ Export          render pipeline: effects flattened BEFORE shapes (blur never smears
                   annotations) → PNG/JPG/TIFF (WPF encoders) · PDF (PDFsharp) ·
                   clipboard ("PNG" + CF_DIB-on-white + CF_BITMAP, retry loop) ·
                   drag-out (temp-PNG CF_HDROP; virtual files later) ·
                   Share sheet (IDataTransferManagerInterop GUID 3A3DCD6C…, GetForWindow +
                   MarshalInterface, SetStorageItems + SetBitmap, handler try/catch,
                   manager kept rooted, UI thread)
```

**License guardrails:** ShareX / Greenshot / Flameshot are GPL — *architecture reference only*,
clean-room, never copy/port code. Copyable references: Text Grab (MIT, WPF fullscreen overlay),
Core2D (MIT, C# shape/handle/undo editor), PowerToys (MIT overlays), swappy (MIT). PDFsharp MIT,
SkiaSharp MIT if ever needed. No QuestPDF (revenue-capped), no iText (AGPL).

## 3. Milestones

Each milestone ends runnable.

- **M0 — Shell** *(skeleton)*: project + manifest + publish profile; tray icon w/ menu
  (Capture region / window / full screen · Open image · Settings · Quit); single instance; global
  hotkey Ctrl+Alt+4; settings JSON; run-at-login toggle. ✔ exe lives in tray, hotkey fires.
- **M1 — Capture engine**: freeze-frame virtual-screen grab; per-monitor overlays; region marquee
  (dim + W×H readout + Esc); window pick w/ highlight; full-screen per-display; timer 3/5/10 s;
  recapture-last; correct on mixed-DPI multi-monitor (the ShareX-bug graveyard — test rig:
  100%+150%+200%). ✔ capture → PNG at physical pixels.
- **M2 — Editor shell**: document window sized-to-capture @100% on active display; rail/top/bottom
  bars w/ design tokens, dark+light; zoom; open-with/drop-on-tray; save-before-close prompt.
- **M3 — Annotation core**: object model, select/move/resize adorners, z-order, undo/redo
  (snapshot), delete; Arrow tool complete (4 head styles + double-head, tapered geometry is the
  signature — get the bezier taper right); Rect/Ellipse/Line/Pen.
- **M4 — Full tool set**: Text (in-place edit, post-hoc re-edit, top-bar restyle) · Highlighter
  (multiply blend) · Obscure ×4 (pixelate/blur/block/stripes, non-destructive, secure-pixelate
  option) · Stamp (check/cross/star/dot + auto-numbered) · Spotlight · Sticker (emoji) · Image
  overlay · Crop (modal bar, W×H, aspect, lock, thirds grid, Esc/Enter) · Rotate/Flip with
  annotations following.
- **M5 — Export & share**: PNG/JPG/TIFF/PDF; format menu on save; clipboard (full-size 1x, format
  trio, retry); drag-out; Windows Share sheet; toast after quick capture.
- **M6 — Capture options**: after-capture actions (show/copy/save combos); quick capture to
  clipboard/file; system-screenshot watcher; rebindable shortcut UI; capture-timer UI.
- **M7 — Polish & v1.5 parity flag**: UIA/Narrator names; keyboard capture; Ctrl+Shift+C; menu bar
  completion; Settings ▸ Editor defaults; localization scaffolding; About.
- **M8 — Ship**: publish pipeline (`dotnet publish` one-liner), smoke matrix (Win10 22H2 ·
  Win11 23H2/24H2 · mixed-DPI · HDR monitor), SmartScreen note: sign with Azure Trusted Signing
  ($9.99/mo, US individuals OK — skip EV, its instant-reputation bypass died in 2024) from the
  first public build with a stable publisher identity — or accept the unsigned-exe reputation grind.

## 4. Risk register

| Risk | Mitigation |
|---|---|
| Mixed-DPI overlay bugs (ShareX issues #1477/#3578/#5312/#8002…) | PMv2 + freeze-frame + **one overlay window per monitor**; physical-px coordinate space everywhere; 3-scale test rig. |
| Hotkey conflicts (Win+Shift+S, PrintScreen) | Never register Win+Shift+S; default Ctrl+Alt+4; optional PrintScreen honoring the OS toggle; all rebindable. |
| Clipboard transparency/format quirks | "PNG" + CF_DIB flattened on white + CF_BITMAP together; retry loop for CLIPBRD_E_CANT_OPEN. |
| Share sheet flakiness | Chromium hardening: try/catch handler (throwing can get the process killed), rooted manager, UI thread, timeout watchdog; copy/save/drag always available as siblings. |
| WGC yellow border on Win10 | Route window capture through frozen-bitmap crop / PrintWindow on Win10; borderless WGC on Win11 (RequestAccessAsync(Borderless) + IsBorderRequired=false). |
| HDR washout (Snipping-Tool-class bug) | v1: document SDR; v1.x: WGC FP16 + DISPLAYCONFIG_SDR_WHITE_LEVEL scale + tone map. |
| GPL contamination | Clean-room rule above; MIT-only code reuse. |
| SmartScreen scare on unsigned exe | Trusted Signing early, stable identity; document the tradeoff. |
| Capture quality complaints (iSkitch's 1-star) | Physical-pixel capture, 1x clipboard, DPI readout — make fidelity a headline. |

## 5. Open product decisions (Josh)

1. **Name** — ~~working title `WinSitch`~~ → resolved: renamed **Sitch** (0.2.0) when the macOS port was planned; one brand for both platforms.
2. **Default hotkey** — `Ctrl+Alt+4` proposed (mirrors ⌥⌘4). PrintScreen as optional alias?
3. **Brand color** — keep iSkitch pink `#FF3366` or differentiate? (Trade-dress: cloning UX/features
   is fine; consider distinct name/icon/accent to keep distance from their branding.)
4. **Distribution** — plain exe on GitHub/website (assumed) vs Microsoft Store later (Store signing
   neutralizes SmartScreen).
5. **Signing budget** — Azure Trusted Signing at ~$10/mo from first public build, or unsigned to start?
