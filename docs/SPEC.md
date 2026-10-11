# Sitch — Feature Specification

A faithful Windows clone of **iSkitch** (iskitch.com, Mac App Store id 6773733499, by Color Vivo
Internet S.L.) — itself a modern native remake of the classic Evernote **Skitch**. This spec is the
single source of truth for *what* we build; `PLAN.md` covers *how*.

**Two platforms.** Written for Windows; the macOS port (`mac/`, `MACOS_PORT.md`) implements the
same spec with the platform mapping in that doc (⌘ for Ctrl, menu bar for tray, …). On the Mac,
Sitch competes with iSkitch on its home platform, so the clean-room rule matters more: match
behavior, never copy iSkitch's assets, copy, or UI text — and the `#FF3366` trade-dress question in
`PLAN.md` is still open.

**Cloned baseline:** iSkitch **v1.4.1** (released 2026-07-03) plus the announced-but-unshipped
**v1.5.0** items behind a "v1.5 parity" flag. Facts below are sourced from iskitch.com (homepage,
FAQ, support, changelog, 4 blog guides, `support.md`/`index.md` agent endpoints), the full-res
2880×1800 App Store screenshots (see `reference/`), the App Store description + embedded
version-history JSON, and Skitch-heritage research. Anything the original never published is marked
**[inferred]** — we choose a sensible value and keep parity-fixable.

---

## 1. Product shape

- **Tray-resident utility** (macOS menu-bar app → Windows system tray). Optional main-window/taskbar
  presence; Settings has "Show in Dock" / "Show in menu bar" toggles with rule *"At least one needs
  to stay active."* → Windows: "Show in taskbar" / "Show in tray".
- Core loop: **hotkey → capture (region / window / full screen) → opens straight in the editor →
  annotate → share/copy/drag/save**. No intermediate dialogs.
- **Privacy-first:** works completely offline, no accounts, no tracking, no analytics, no telemetry.
  Captures never leave the machine unless the user shares them.
- **Never saves silently:** the user picks the destination via Save dialog or drag-out. (Default save
  folder + default format are configurable in Settings ▸ Capture.)
- Single document per editor window; window title `{Document name} — Sitch` (e.g. `Untitled — Sitch`).
- Light / Dark / System appearance.
- Localizable (iSkitch ships 8 languages: EN ES FR DE IT PT JA KO). English-first for v1, resource-based strings from day one.

## 2. Capture

| Feature | Behavior |
|---|---|
| Region capture | Default hotkey (iSkitch: ⌥⌘4 → **Sitch default: `Ctrl+Alt+4`**, rebindable). Crosshair drag over a **frozen** frame of the desktop. Opens straight in editor. |
| Window capture | Same overlay; hover highlights a window (DWM extended-frame bounds, no shadow); click captures it — including occluded windows. |
| Full screen | Captures a chosen display (multi-display: pick which screen, v1.3.0). |
| Recapture last region | Repeat exact same region without selecting again (iSkitch: ⇧⌥⌘4 → **`Ctrl+Alt+Shift+4`**). |
| Capture timer | 3 / 5 / 10 s countdown before the shot (v1.3.0). |
| Quick capture | Region or full screen straight to **clipboard or file**, skipping the editor (v1.3.0). |
| After-capture actions | Configurable, "Shottr-style", any combination of: **Show editor / Copy to clipboard / Save to file**. Default: show editor **+ copy to clipboard** (deliberate deviation from iSkitch's editor-only default — paste-ready immediately). |
| System-screenshot watcher | "Open the editor automatically after a system screenshot" — watches where the OS saves screenshots (v1.2.0). Windows analog: watch `%USERPROFILE%\Pictures\Screenshots` (Win+PrtScn) — **[adapted]**, off by default. |
| Multi-display | Region/window capture on any display; editor opens on the display you're working on (v1.4.0; full any-display capture is v1.5.0 parity). |
| Open existing images | Drop an image onto the tray/Dock icon or "Open with Sitch" from Explorer → opens straight in the editor. |
| Capture fidelity | Capture at **physical pixels** (per-monitor DPI). Copy to clipboard at full size (1x) so high-DPI shots paste at full resolution (v1.3.0). Editor shows a size + DPI readout. *iSkitch's only App Store review is 1-star for "very poor capture quality" — capture fidelity is a differentiation opportunity.* |

Region overlay UX (from Skitch/ShareX conventions, iSkitch unpublished — **[inferred]**): dimmed
frozen desktop, undimmed marquee, live W×H readout, crosshair cursor, `Esc` cancels; three-stage
escape (cancel drag → deselect → close overlay).

## 3. Editor window

- First-ever editor opens **sized to the capture at 100% zoom** when it fits on screen, on the
  active display (v1.4.0). Thereafter the editor **remembers the last closed window size**
  (Windows convention — deliberate deviation) and shows the capture at 100% if it fits, else fit-zoom.
- **Top bar** (contextual per tool): `[📷 New Capture]` button · active tool icon + name in pink ·
  tool options (see §5).
- **Left tool rail**, exact order (14): **1 Select, 2 Arrow, 3 Text (Aa), 4 Rectangle, 5 Ellipse,
  6 Line, 7 Highlighter, 8 Obscure (checkerboard icon), 9 Stamp, 10 Pen, 11 Spotlight,
  12 Sticker (emoji), 13 Image, 14 Crop** — then a separator and a round **current-color well**
  pinned at the bottom.
- **Bottom bar**: left `undo · redo · trash` · divider · `zoom-out · ⌄ NN% (dropdown) · zoom-in`;
  right `drag-out hand · copy · [⤓ .jpg ⌄] format+save menu · share`.
- **Precision cursors**: every drawing tool + crop shows a crosshair with a mini icon of the active
  tool, hotspot at cross center, crisp at all DPIs (v1.4.0).
- **Menus** (main window menu bar): `File · Edit · Capture · Image · Tools · Window`.
  Documented items: Image → Rotate Left, Rotate Right, Flip Horizontal, Flip Vertical, Crop.
  Edit gains Copy Image (`Ctrl+Shift+C`) + Undo/Redo items at v1.5 parity. Others **[inferred]**
  from tool/capture lists.
- Save-before-close warning on window close and app quit with unsaved annotations (v1.1.0).
- Full **undo/redo on every change** (`Ctrl+Z` / `Ctrl+Y`), including text edits, crop, rotate.

### Design tokens (sampled from full-res screenshots)

| Token | Dark | Light |
|---|---|---|
| Title bar | `#2C2D2E` | `#FAFAFC` |
| Top/left/bottom bars | `#1E1E1E` | `#FAFAFC` / rail `#EFEFF3` |
| Canvas well | `#282828` (lighter than bars) | — |
| Selected tool tile | `#45242B` bg, `#FF3366` glyph | `#FFE4EC` bg, `#FF3366` glyph |
| Unselected glyph | `#AFAFAF`–`#E5E5E5` | dark gray |
| Apply/primary button | `#007AFF` | same |
| Brand pink | `#FF3366` (site theme-color; default swatch; selected-tool tint) | |

**Color palette** — 10 swatches, in order: `#FF3366` (pink, **default**), `#FF9500` orange,
`#FFD60A` yellow, `#34C759` green, `#2E7DF6` blue (deliberately not Apple systemBlue — match it),
`#5E5CE6` indigo, `#AF52DE` purple, `#1D1D1F` black, `#FFFFFF` white, + rainbow **custom color
picker** button (pink center dot). No selected-ring on swatches; current color shows in the rail's
bottom color well.

**Stroke width control** — 5 graduated preset buttons + an **editable numeric field** with `px`
suffix (observed default for Arrow: **20**). Not a slider, not a stepper. Preset bar thicknesses
scale roughly 3/5/9/17/27 **[exact preset px values inferred: 2/4/8/16/28]**.

## 4. Annotation model (non-negotiable architecture facts)

- Pristine capture bitmap is **immutable**; every annotation — including obscure effects — is a
  vector/effect **object** in an ordered list, movable/editable until export.
- Obscure effects re-render from the live composition beneath them each frame (non-destructive);
  they are **flattened destructively only at export**, applied *before* vector shapes so blur never
  smears annotations.
- Select tool: hit-test topmost-first, 8 resize handles + move; `Delete` removes; objects keep
  z-order (bring-forward/send-back via menu **[inferred]**).
- Text annotations re-editable after creation: double-click with Select, or click existing text with
  the Text tool; selecting a text shows its color/font/size/bold/italic in the top bar for restyling
  (v1.4.1). New text keeps the chosen font from the first character.

## 5. The 14 tools

| # | Tool | Options (top bar) & behavior |
|---|---|---|
| 1 | **Select** | Move/resize/edit any annotation; handles; delete. |
| 2 | **Arrow** | The icon. **Tapered Skitch-style** (default) + **filled, open, concave** head styles; separate **double-headed** toggle. Swatches + width (default 20 px). Drawn tail→tip; movable/resizable/rotatable after placement. |
| 3 | **Text** | Any system font, size, **bold/italic**. Swatches. Editable post-hoc (§4). Auto-select text tool behavior on typing **[Skitch heritage, inferred]**. |
| 4 | **Rectangle** | **Outline or filled**; swatches + width. |
| 5 | **Ellipse** | Outline or filled; swatches + width. |
| 6 | **Line** | Straight line; swatches + width. |
| 7 | **Highlighter** | Translucent wash, **multiply blend** ("just like a real marker"); yellow default **[inferred]**; width control. |
| 8 | **Obscure** | Four styles in toolbar: **Pixelate, Blur, Solid block, Stripes**. All "reliably unreadable" — pixelate must compute from full-res source; offer Flameshot-style secure pixelate (fringe-pixel synthesis) so content is unrecoverable. Solid block recommended for real secrets. |
| 9 | **Stamp** | **Check, cross, star, dot** + **numbered stamps 1·2·3 that auto-increment** (v1.3.0, "perfect for tutorials and runbooks"). Colors/sizes unpublished → reuse shared swatch + px bar **[inferred]**. |
| 10 | **Pen** | Freehand; swatches + width. |
| 11 | **Spotlight** | **Dim everything except the region(s) you care about.** Rectangular region (rail icon = corner brackets); multiple regions supported (store copy plural in 5/8 locales) **[inferred: allow multiple]**; dim strength fixed **[inferred: ~55%]**. |
| 12 | **Sticker** | Emoji stickers; picker UI unpublished → standard emoji flyout **[inferred]**. |
| 13 | **Image** | Image-over-image overlay: insert a picture file onto the canvas; move/resize. |
| 14 | **Crop** | **Non-destructive**, modal top-bar takeover: `W × H` numeric fields · `Free ⌄` aspect-ratio dropdown · padlock (proportional lock) · `Cancel` · blue `Apply`. Rule-of-thirds grid, 8 white/pink handles, dimmed surround. Opens fit-to-window with **everything selected by default** (v1.2.2); annotations visible while cropping (v1.3.0); `Esc` cancels / `Enter` applies (v1.5 parity). Aspect preset list unpublished → **[inferred: Free, Original, 1:1, 4:3, 3:2, 16:9]**. |

**Image operations:** Rotate left/right, flip horizontal/vertical — **annotations follow** the
transform. Undoable.

## 6. Export & sharing

- **Formats: PNG, JPG, PDF, TIFF** (blog copy sometimes omits TIFF; store + support.md include it).
- **Save**: dedicated format menu on the save button (`.png ⌄` / `.jpg ⌄` …); Save dialog every time
  unless default folder set. Redactions/effects flatten into the pixels at export.
- **Copy to clipboard**: full-size 1x; instant + confirmation (v1.5 parity). Write `PNG` +
  `CF_DIB` (flattened onto white) + `CF_BITMAP` together, retry on `CLIPBRD_E_CANT_OPEN`.
- **Drag-out**: bottom-bar hand affordance + drag from canvas → any app (Explorer, browser, Slack,
  mail). Temp-file `CF_HDROP` first, virtual-file later. *(Spiritual descendant of Skitch's "Drag
  Me" tab.)*
- **Share**: native **Windows Share sheet** (`IDataTransferManagerInterop`, works unpackaged; set
  `SetStorageItems` + `SetBitmap`, title required).
- **Quit/close** honors unsaved-changes warning.

## 7. Settings (3 tabs)

- **General**: Appearance (System/Light/Dark radio cards) · Language (System + 8) · Behavior:
  Show in taskbar / Show in tray ("at least one stays active") · Open at login.
- **Capture**: Shortcut (rebindable) · default save folder · default export format (PNG/JPG/PDF/TIFF)
  · After-capture actions (show/copy/save, any combo) · timer · system-screenshot watcher.
- **Editor**: per-tool defaults **[contents never published — inferred: default color, width,
  font/size, obscure style, remember-last-tool]**.
- Store: JSON in `%APPDATA%\Sitch\settings.json` (iSkitch uses UserDefaults).

## 8. Shortcut map (Windows)

| Action | iSkitch (macOS) | Sitch |
|---|---|---|
| Capture (region/window/full) | ⌥⌘4 (rebindable) | **Ctrl+Alt+4** (rebindable) |
| Recapture last region | ⇧⌥⌘4 | **Ctrl+Alt+Shift+4** |
| Quick capture → clipboard | — | **Ctrl+Alt+Shift+C** *(Sitch addition; Mac port ⌃⌥⌘4)* |
| Undo / Redo | ⌘Z / ⇧⌘Z | Ctrl+Z / Ctrl+Y (+Ctrl+Shift+Z) |
| Copy image | ⌘⇧C (v1.5) | Ctrl+Shift+C *(v1.5 parity)* |
| Quit w/ unsaved warning | ⌘Q | Alt+F4 / close |
| Crop confirm/cancel | Return / Esc (v1.5) | Enter / Esc *(v1.5 parity)* |
| Keyboard-defined capture | arrows + Return (v1.5) | arrows + Enter *(v1.5 parity)* |

No tool-switch mnemonics or zoom hotkeys exist in shipped iSkitch 1.4.1 — don't invent them for
strict fidelity (optional later; ShareX uses letters + numpad).

Never bind `Win+Shift+S` (Explorer owns it; `RegisterHotKey` fails). Optional PrintScreen binding
honoring `HKCU\Control Panel\Keyboard\PrintScreenKeyForSnippingEnabled`.

## 9. v1.5.0 parity flag (announced, unshipped upstream)

VoiceOver→ **UIA/Narrator** naming of controls/tools/colors/annotations with state · full keyboard
capture (arrows move/define selection, Enter confirms) · Edit-menu Copy `Ctrl+Shift+C` + Undo/Redo
items · instant copy + clipboard-capture confirmation toast · keyboard crop (Esc/Enter) ·
region/window capture on any display.

## 10. Known unknowns (parity-fixable defaults)

Zoom dropdown presets · crop aspect preset list · sticker picker set · spotlight dim/multi-region ·
highlighter/pen default widths & opacity · stamp colors/sizes · text size range/default font ·
Settings ▸ Editor tab contents · Edit/File/Capture/Tools/Window full menu items. Resolvable only by
running the $9.99 app on macOS 14+ or asking hello@iskitch.com. We ship **[inferred]** choices and
adjust if ground truth appears.

## 11. Anti-goals (lessons from Skitch 2.0's 1.5-star collapse)

No accounts · no cloud lock-in · no subscription · no removal of format choice · no tool sprawl —
the small fixed palette, one-slider-ish width control, and ≤14-tool rail are the product.
