<div align="center">

<img src="windows/Sitch/Assets/sitch.ico" width="80" alt="Sitch — Skitch alternative for Windows and Mac (screenshot annotation tool)"/>

# Sitch — Skitch for Windows and Mac

**The Skitch alternative for Windows and macOS.** Capture any region, window or full screen,
mark it up with the iconic tapered arrow, and share it — in seconds, offline, for free.

[![MIT License](https://img.shields.io/badge/license-MIT-ff3366)](LICENSE)
[![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078d4)](#requirements)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-000000)](#requirements)
[![Apple Silicon + Intel](https://img.shields.io/badge/Mac-Apple%20Silicon%20%2B%20Intel-555555)](#requirements)

### [⬇️ Download for Windows](https://github.com/phalladar/sitch/releases/latest/download/WinSitch.exe) &nbsp;·&nbsp; [⬇️ Download for Mac](https://github.com/phalladar/sitch/releases/latest/download/Sitch.dmg)

**Windows:** one standalone .exe — no installer, no .NET to install.
**Mac:** a native, signed and notarized app — open the disk image, drag to Applications.
*(Formerly **WinSitch**.)*

*Capture. Annotate. Share.* — [Screenshots ↓](#screenshots)

</div>

---

## Is there a Skitch for Windows? For Mac?

Not anymore. Evernote discontinued **Skitch for Windows in January 2016**, and the Mac version
was abandoned after 2020 — it never got an Apple Silicon build and no longer runs properly on
modern macOS. If you've been googling *"Skitch for Windows download"*, *"Skitch alternative for
Mac"*, or *"Evernote Skitch replacement"* — this is that tool, rebuilt natively for both.

Sitch is a free, open-source (MIT) screenshot annotation tool that keeps everything people
loved about Skitch:

- 📸 **Snap-and-mark-up flow** — press a hotkey, drag a region, and the shot opens straight in
  the editor. No dialogs, no file hunting.
- ➹ **The iconic tapered arrow** — thick at the base, fine at the tip. Plus filled, open,
  concave and double-headed variants.
- 🔒 **Privacy first** — no accounts, no tracking, no telemetry, works completely offline.
  Nothing you capture ever leaves your computer.
- 🖥️ **Truly native on both** — WPF on Windows, Swift/AppKit on the Mac. Not a web wrapper,
  not Electron.

## Features

**Capture**
- One hotkey, every mode: `Ctrl+Alt+4` on Windows, `⌘⌥4` on Mac (**fully configurable**) —
  drag a region, or just *click* a window to capture it, or pick a display from the tray /
  menu bar
- Keyboard capture: arrow keys define and nudge the selection, `Enter` / `Return` confirms
- Recapture the last region with one keystroke
- Freeze-frame picker with live size readout — correct on multi-monitor, mixed-DPI and Retina
  setups
- Window picker that captures clean window content even when partially covered
- Capture timer (3/5/10 s), quick capture straight to clipboard or file
- **Every capture is copied to the clipboard automatically** (on by default) — paste into chat
  before you've even annotated; configurable after-capture actions: show editor / copy / save
- Optional watcher that opens the editor after a system screenshot (`Win+PrtScn` on Windows,
  `⌘⇧3` / `⌘⇧4` / `⌘⇧5` on Mac)

**Annotate — 14 tools**
Select · **Arrow** (tapered/filled/open/concave, double-headed) · Text (any system font, bold,
italic, re-editable later) · Rectangle · Ellipse · Line · Highlighter · **Obscure**
(pixelate / blur / solid block / stripes) · Stamps (✓ ✕ ★ ● + auto-numbering 1·2·3) · Pen ·
**Spotlight** (dim everything but the point you're making) · Emoji stickers · Image overlay ·
non-destructive Crop with aspect-ratio presets

- Everything stays an editable object until export — move, restyle, or delete any mark later
- Redactions are computed from the full-resolution source and flattened only when you export
- Full undo/redo on every change; rotate/flip with annotations following
- Dark, light, or system theme

**Share & export**
- Export **PNG, JPEG, PDF, TIFF**
- Copy to clipboard at full resolution — high-DPI shots paste pixel-perfect
- **Drag the image out** of the editor straight into Slack, Teams, Mail, or any app
- Native **share sheet** on both platforms
- Never saves silently — you always choose where files go

## Download

Both downloads are on the [Releases page](https://github.com/phalladar/sitch/releases).

### Windows

**[⬇️ Download Sitch for Windows](https://github.com/phalladar/sitch/releases/latest/download/WinSitch.exe)**
— a single self-contained ~86 MB file with the .NET runtime baked in. Run it; it lives in your
system tray. That's the whole install. Delete the file to uninstall.

> Windows SmartScreen may warn on first run (the build is currently unsigned). Choose
> *More info → Run anyway*, or build it from source below.

### Mac

**[⬇️ Download Sitch for Mac](https://github.com/phalladar/sitch/releases/latest/download/Sitch.dmg)**
— open the disk image and drag Sitch to Applications. It's a universal app (Apple Silicon and
Intel), signed and notarized by Apple, so it opens without Gatekeeper warnings. Sitch lives in
your menu bar; on first launch it walks you through granting **Screen Recording** permission
(System Settings ▸ Privacy & Security), which macOS requires for any screenshot app.
A plain [.zip](https://github.com/phalladar/sitch/releases/latest/download/Sitch-macOS.zip)
of the app is also available.

## Usage

| Action | Windows | Mac |
|---|---|---|
| Capture (drag = region, click = window) | `Ctrl+Alt+4` | `⌘⌥4` |
| Recapture last region | `Ctrl+Alt+Shift+4` | `⌘⌥⇧4` |
| Quick capture to clipboard (skips the editor) | `Ctrl+Alt+Shift+C` | `⌃⌥⌘4` |
| Keyboard capture in the overlay | arrows move · `Shift`+arrows resize · `Enter` confirms | arrows move · `⇧`+arrows resize · `⌥` for 10-pt steps · `Return` confirms |
| Undo / Redo | `Ctrl+Z` / `Ctrl+Y` | `⌘Z` / `⌘⇧Z` |
| Copy flattened image | `Ctrl+C` / `Ctrl+Shift+C` | `⌘C` |
| Save | `Ctrl+S` | `⌘S` |
| Zoom | `Ctrl` `+` / `−` / `0`, `Ctrl`+wheel | `⌘=` / `⌘−` / `⌘0`, `⌘9` to fit |
| Crop: apply / cancel | `Enter` / `Esc` | `Return` / `Esc` |
| Straight lines / squares while drawing | hold `Shift` | hold `⇧` |

All three capture hotkeys are configurable in Settings ▸ Capture.

**Windows:** left-click the tray icon to capture; right-click it for window capture, full-screen
per display, quick capture, the timer, and Settings.
**Mac:** click the menu-bar icon for region, window and full-screen capture, quick capture,
and Settings.

## Sitch vs. Skitch

| | Skitch (Evernote) | **Sitch** |
|---|---|---|
| Windows support | ❌ discontinued Jan 2016 | ✅ Windows 10 & 11 |
| Mac support | ⚠️ abandoned, no Apple Silicon build | ✅ macOS 15+, universal (Apple Silicon + Intel) |
| Tapered arrows | ✅ | ✅ (+3 more styles, double-headed) |
| Pixelate | ✅ | ✅ + blur, solid block, stripes |
| Spotlight, stickers, numbered stamps | ❌ | ✅ |
| Account required | Evernote | **None** |
| Cloud upload | forced | **Never** — fully offline |
| Price | — | **Free, MIT open source** |

## FAQ

**What happened to Skitch?**
Evernote bought Skitch in 2011, killed the Windows, iOS and Android versions in January 2016,
and shipped the Mac version's last meaningful update in 2020. It never got an Apple Silicon
build and now crashes on modern macOS.

**Is Sitch really free?**
Yes — free and MIT-licensed. No accounts, no subscription, no "pro" tier, no tracking.

**Which versions of Windows and macOS does it support?**
Windows 10 version 1903 or later, and every Windows 11 release. macOS 15 Sequoia or later, on
both Apple Silicon and Intel Macs.

**Why does the Mac version ask for Screen Recording permission?**
macOS requires it for any app that reads the screen, including every screenshot tool. Sitch
uses it only to capture what you select — nothing is recorded, uploaded or stored without you
saving it.

**Does it handle multiple monitors and display scaling?**
Yes — capture grabs true physical pixels on mixed-DPI Windows setups and Retina Macs alike.

**How do I hide passwords or secrets in a screenshot?**
Use the Obscure tool. For real secrets prefer **solid block or stripes** — blur and pixelation
are filters and can sometimes be partially reversed. Sitch flattens redactions into the
pixels when you export, so nothing can be "un-hidden" from the file.

**Can I change the capture hotkey?**
Yes — Settings ▸ Capture, click the shortcut field, and press any combination.

## Requirements

**Windows**
- Windows 10 1903+ or Windows 11 (x64)
- No runtime, no installer, no admin rights required

**Mac**
- macOS 15 Sequoia or later
- Apple Silicon or Intel
- Screen Recording permission (requested on first launch)

## Building from source

**Windows** — requires the [.NET 10 SDK](https://dotnet.microsoft.com/download). No other
dependencies.

```powershell
git clone https://github.com/phalladar/sitch
cd sitch
dotnet publish windows/Sitch/Sitch.csproj -c Release -r win-x64 -o publish
# → publish/Sitch.exe  (self-contained single file)
```

**Mac** — requires Xcode 16 or later (or its command-line tools). No third-party dependencies.

```sh
git clone https://github.com/phalladar/sitch
cd sitch/mac
swift test                 # core unit tests
./scripts/build-app.sh     # → .build/Sitch.app (ad-hoc signed)
```

## Known limitations

- Windows: emoji stickers render monochrome on some systems (WPF color-font limitation)
- Windows: the binary is unsigned, so SmartScreen shows a first-run warning
- Mac: a region capture stays on the display where the drag started
- HDR displays are captured in SDR (tone-mapped capture is on the roadmap)

## Architecture notes

Two native apps in one repo, built to the same spec and released together: WPF on .NET 10 for
Windows (`windows/`), Swift and AppKit with ScreenCaptureKit for the Mac (`mac/`). Both use
freeze-frame capture with one overlay window per display, in a physical-pixel coordinate space
— the approach that avoids the classic mixed-DPI capture bugs. The pristine capture is
immutable: every annotation, including blur/pixelate, is a vector object rendered
non-destructively and flattened only at export, with effects applied before shapes so
redactions never smear your arrows. Clean-room implementation; architecture lessons drawn from
studying the classic Skitch, its modern macOS remake [iSkitch](https://iskitch.com), and the
open-source annotation-tool ecosystem.

## Screenshots

*The editor — dark theme, with the signature tapered arrow, highlighter, pixelate redaction and
a numbered-workflow stamp:*

![Sitch screenshot editor in dark mode — Skitch-style tapered arrow, highlighter and pixelate redaction on Windows](docs/assets/editor-dark.png)

*On the Mac — the same editor, native to macOS:*

![Sitch screenshot annotation editor on macOS — Skitch-style tapered arrow and pixelate redaction](docs/assets/editor-mac.png)

*Region capture — frozen-screen picker with dimming and a live pixel-size readout:*

![Region capture overlay — select any screen region to screenshot and annotate](docs/assets/region-capture.png)

*Non-destructive crop with aspect-ratio presets, proportional lock and rule-of-thirds grid:*

![Crop mode with exact width and height fields and rule-of-thirds grid](docs/assets/crop-mode.png)

*Light theme:*

![Sitch screenshot annotation editor in light mode on Windows 11](docs/assets/editor-light.png)

*Settings — the capture hotkey is fully configurable:*

![Sitch settings — configurable screenshot hotkey, formats and after-capture actions](docs/assets/settings.png)

---

<div align="center">

**Sitch** — screenshot annotation for Windows and Mac: capture, annotate & share.
A free, open-source Skitch replacement. MIT © 2026 Josh Auriemma

</div>
