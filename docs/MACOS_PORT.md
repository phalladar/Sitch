# macOS port — roadmap

Proposal adopted 2026-10-11 (WinSitch → **Sitch**; native Swift Mac app in `mac/`; one repo, one
release per version carrying both platforms). Kept here as the plan of record for the remaining
phases; update the status table as phases land.

## Status

| Phase | State |
|---|---|
| 0 — Rebrand + restructure | **Done.** `windows/Sitch`, legacy settings / login-item migration. |
| 1 — Mac scaffold + pipeline | **Code done.** Menu-bar stub, icon, scripts, workflows; Developer ID signing verified locally. **Done.** Repo renamed to `phalladar/sitch`; signing secrets set; `v0.2.0-rc1` dry run and **v0.2.0 released (2026-10-11)** with both platforms — CI notarization verified, Gatekeeper accepts the DMG. |
| 2–6 — Port | **Done, released in v0.2.0 (2026-10-11).** Core + 17 unit tests; Editor, Capture, Export, Shell ported. Verified on a 1x ultrawide: demo render parity, editor actions, real region/window/full-screen/recapture/quick captures, save/copy, quit prompt, single-instance forwarding, notarization of the full app. Not yet exercised: Retina/mixed-DPI capture, share sheet, open-at-login toggle, the Screen Recording prompt flow (the dev machine already had the grant). |

Deviations from the original proposal, decided while building phase 1:
- CI is two path-filtered workflows (`build-mac.yml`, `build-windows.yml`) instead of one `build.yml`.
- `SitchCore` + `swift test` arrived in phase 2 and run in `build-mac.yml`.
- Phases 2–6 were built in parallel by separate agents against contract stubs (one per module).
- A capture region is confined to the display the drag started on; keyboard 10-pt nudge is ⌥
  (Ctrl+arrows belong to Mission Control).
- `CFBundleDocumentTypes` waits until opening images works (phase 3), so "Open With" never offers
  a no-op.
- The README download link keeps the `WinSitch.exe` asset name (every release attaches it);
  switch it to `Sitch.exe` whenever convenient.

## Context
WinSitch was a Windows-only WPF app: 6.8k lines of C#, Skitch-style capture and annotation. The goal is a macOS version, signed and notarized the same way as MacDirStat (`phalladar/MacDirStat`).

Decisions:
- **Native Swift** for the Mac app.
- **One shared repo.**
- **Rebrand the whole product to "Sitch"** on both platforms.

Facts that shaped the plan:
- **No code can be shared.** Even the "pure" Core model is built on WPF types (`Point`, `Color`, `BitmapSource`, `DrawingContext`). The Mac app is therefore a faithful translation. `docs/SPEC.md` and the invariants in `docs/ARCHITECTURE.md` are the contract both platforms must meet.
- **MacDirStat's pipeline** is small and easy to copy:
  - It's a SwiftPM project. `scripts/build-app.sh` builds the `.app` and writes its Info.plist with a heredoc. It signs with `codesign --options runtime --timestamp` and no entitlements.
  - `scripts/notarize.sh` runs `notarytool` with an App Store Connect API key, then `stapler`, then zips with `ditto`.
  - `scripts/smoke-test.sh` checks the app doesn't crash at launch.
  - `.github/workflows/release.yml` runs on `v*` tags on `macos-26`. It imports the `.p12` into a temporary keychain along with Apple's Developer ID intermediate certificates, then runs `gh release create`.
  - It relies on five secrets: `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `NOTARY_API_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`.
  - The signing identity is `Developer ID Application: Mind Meat Machine, LLC (G99WQY2ZW3)`.
- **The shared "Latest" release breaks a download link.** In one repo, the README's `releases/latest/download/WinSitch.exe` link breaks as soon as a Mac-only release becomes "Latest". So **every release must carry both platforms' assets**, built by one workflow.

## Target repo layout
```
sitch/                         (GitHub repo renamed phalladar/winsitch → phalladar/sitch; old URLs redirect)
├─ windows/Sitch/Sitch.csproj  (git mv of src/WinSitch; namespaces WinSitch.* → Sitch.*)
├─ mac/                        (SwiftPM package, layout copied from MacDirStat)
│  ├─ Package.swift            swift-tools 6.0, .macOS(.v15), Swift 6 language mode
│  ├─ Sources/SitchCore/       library: model, renderer, effects, settings (CoreGraphics only, no AppKit)
│  ├─ Sources/Sitch/           executable: App, Capture, Editor, Export, Shell (AppKit + some SwiftUI)
│  ├─ Tests/SitchCoreTests/    swift test (Windows has no test harness; the Mac core gets one cheaply)
│  ├─ scripts/build-app.sh  notarize.sh  smoke-test.sh   (adapted from macdirstat)
│  └─ CLAUDE.md                Mac-specific notes (nested, loaded when working under mac/)
├─ docs/  ARCHITECTURE.md (+ macOS section) SPEC.md (platform mapping table) PLAN.md
├─ .github/workflows/build.yml  release.yml
└─ CLAUDE.md  README.md  LICENSE
```

## Phase 0: Rebrand and restructure (Windows only, no behavior change)
- **Move the project.** `git mv src/WinSitch windows/Sitch`, rename the csproj to `Sitch.csproj` (AssemblyName becomes `Sitch`), rename the icon to `sitch.ico`, and change namespaces to `Sitch.*`.
- **Update user-facing strings:** window titles, MessageBox captions, the tray tooltip and About box, the welcome text, the "already running" toast, and the PDF `Creator` field.
- **Migrate persisted identifiers** so existing users don't lose anything:
  - **Settings:** `AppSettings.cs:57` changes `%APPDATA%\WinSitch` to `%APPDATA%\Sitch`. On load, if the new file is missing and the old one exists, copy the old one over.
  - **Login item:** `StartupManager.cs:10` changes the Run value name. Delete any `WinSitch` Run/StartupApproved entries, then re-register as `Sitch` if `OpenAtLogin` is on.
  - **Default save location:** `Exporters.cs:63` changes the default `Pictures\WinSitch` to `Pictures\Sitch`. A `DefaultSaveFolder` the user set explicitly is kept. Quick-save names change from `WinSitch yyyy-…` to `Sitch yyyy-…`.
  - **Mutex, pipe and hotkey window** (`SingleInstance.cs:11-12`, `HotkeyManager.cs:26`): rename them. If an old WinSitch process is still running, both apps will try to register `Ctrl+Alt+4`. The existing hotkey-failure path covers that, so add one line to the release notes ("quit WinSitch first").
  - **Temp folders:** the drag-out and share temp directories become `%TEMP%\Sitch`.
- **Update docs:** README, CLAUDE.md (new build path `windows/Sitch/Sitch.csproj`; the release section now says "push a tag"), ARCHITECTURE, SPEC and PLAN.
  - SPEC currently calls the app a *Windows* clone of iSkitch. With a Mac build, Sitch competes with iSkitch on its own platform. The clean-room rule still holds: never copy iSkitch's assets, copy or UI text.
  - PLAN already flags the `#FF3366` trade-dress question as open. It matters more now.
- **Before renaming, check that "Sitch" is free:** search the Mac App Store and GitHub for an existing app or trademark with that name.

## Phase 1: Mac scaffold and a signing pipeline that works end to end (de-risk first)
A menu-bar stub (status item → "Open Editor" → empty window) is enough to prove signing, notarization and releasing before any real porting starts.

**`mac/scripts/build-app.sh`** is a copy of macdirstat's with these changes:
- `BUNDLE_ID="io.github.phalladar.Sitch"`; the app name and executable are `Sitch`.
- Extra Info.plist keys:
  - `LSUIElement` = true. Sitch is a menu-bar app; while an editor is open it switches to `.regular` activation so a Dock icon shows. That is the Mac equivalent of the "Show in taskbar" setting.
  - `NSHumanReadableCopyright`.
  - `CFBundleDocumentTypes` for png/jpg/tiff/heic/webp, so images can be opened with "Open With" or dropped on the icon.
  - `LSMinimumSystemVersion` = 15.0, matching MacDirStat. `SCScreenshotManager` only needs 14.
- **No entitlements file, same as MacDirStat.** None of Sitch's features need one under the hardened runtime:
  - Screen capture is controlled by the Screen Recording privacy permission, not an entitlement.
  - Carbon hotkeys need no permission.
  - The app makes no network calls.
- **Icon:** the `.ico` only goes up to small sizes, so we need a 1024 px master PNG. From it, generate `AppIcon.iconset` with `sips` and build `AppIcon.icns` with `iconutil`, then commit the `.icns` (as MacDirStat does). The menu-bar glyph is a separate template image.

**`mac/scripts/notarize.sh` and `smoke-test.sh`** are copied unchanged apart from the names. The asset is **`Sitch-macOS.zip`**.

**`.github/workflows/release.yml`** runs on a `v*` tag with three jobs:
1. **`windows`** (`windows-latest`):
   - Fail if the tag doesn't match `<Version>` in the csproj. The other three places the version lives are checked with grep.
   - `dotnet publish windows/Sitch/Sitch.csproj -c Release -r win-x64 -o publish`, then upload `Sitch.exe`.
   - This automates what is a manual release today.
2. **`mac`** (`macos-26`, `working-directory: mac`): macdirstat's steps verbatim.
   - Temporary keychain, then import the Apple intermediate certificates and the `.p12`.
   - `UNIVERSAL=1 VERSION=${GITHUB_REF_NAME#v} ./scripts/build-app.sh`
   - Smoke test.
   - `notarize.sh Sitch-macOS.zip`, then upload it.
3. **`release`** (needs both jobs): download both artifacts, then:
   - Run `gh release create "$TAG" Sitch.exe Sitch-macOS.zip WinSitch.exe --verify-tag --generate-notes --title "Sitch X.Y.Z"`. Add `--prerelease` when the tag contains `-`, so `-rc` tags never become Latest.
   - The extra `WinSitch.exe` is a copy of `Sitch.exe`. It keeps old `releases/latest/download/WinSitch.exe` links working for a few releases.

**`.github/workflows/build.yml`** runs on pushes to main and on PRs:
- Mac: `swift build`, `swift test`, smoke test.
- Windows: `dotnet build`.
- Path filters so each job only runs when its platform changed.

**Secrets:** set the same five names on the renamed repo with `gh secret set`. GitHub secrets can't be read back, so the `.p12` and `.p8` must be supplied again; they can't be copied from MacDirStat.

**Versioning:**
- One joint version line.
- On Windows the version still lives in its four places, which CI now enforces.
- On Mac the version comes from the tag, as in MacDirStat.
- The first joint release is **Sitch 0.2.0**. Until Mac reaches parity, the README labels it "macOS (preview)".
- Pipeline dry run: push `v0.2.0-rc1` → pre-release with both assets → download the zip on another Mac or user account → it opens with no Gatekeeper prompt.

## Phases 2–6: the Mac port, module by module

| WinSitch (C#) | Sitch for Mac (Swift) |
|---|---|
| `Core/Annotation*.cs`, `Document.cs` (snapshot undo, crop, rotate/flip) | `SitchCore`: value types on `CGPoint`/`CGRect`/`CGColor`, logic ported 1:1 |
| `Core/Renderer.cs`: base → obscure → spotlight dim → marks | Same order, drawn on a `CGContext`. Spotlight uses an even-odd fill of the full rect minus the spotlight rects |
| `EffectRenderer` (pixelate block = min(w,h)/12 clamped 10–56; blur = 4 box passes r=12; always samples the original) | Port the byte loops directly over a BGRA `CGContext` buffer, so output matches Windows pixel for pixel. Same per-annotation cache key |
| Text (`FormattedText`, Segoe UI, offset halo); emoji stickers | Core Text / `NSAttributedString`, system font; Apple Color Emoji |
| `Capture/` (GDI freeze of the whole virtual screen, overlay per monitor, physical pixels) | `SCScreenshotManager` grabs each display at native pixel scale. One borderless overlay window per `NSScreen` at screen-saver level shows the frozen frame. Regions are limited to one display, as macOS's own ⇧⌘4 does. Window mode uses `SCShareableContent` plus a desktop-independent window filter, which gives a clean window grab |
| Coordinate invariant: physical vs document pixels | Same rule on Mac: `Capture/` works in display pixels plus global points (origin bottom-left, so the y-axis flips). Core uses document pixels. The editor converts to points through `backingScaleFactor`. Recorded in ARCHITECTURE.md |
| `Editor/` (XAML, DocumentCanvas, 14-tool rail, tabs) | `NSWindow` with native window tabbing, a `DocumentCanvas` `NSView`, and the rail built in code. `ToolIcons` path data becomes `CGPath`/SF Symbols where they fit. Ctrl shortcuts become ⌘ |
| `Export/Exporters.cs` (PNG/JPG q92/TIFF; PDF via PDFsharp) | `CGImageDestination` for PNG/JPG/TIFF. **PDF via `CGContext(consumer:mediaBox:)`**, so no third-party dependency |
| `ClipboardHelper` (PNG + flattened DIB) | `NSPasteboard` with PNG plus TIFF |
| `ShareHelper` (COM DataTransferManager) | `NSSharingServicePicker` |
| Drag-out (temp PNG + image) | `NSDraggingSource` with a file URL in `$TMPDIR/Sitch` plus the image |
| `HotkeyManager` (`RegisterHotKey`) | Carbon `RegisterEventHotKey`, which needs no Accessibility permission. Defaults ⌥⌘4 / ⇧⌥⌘4 (SPEC §8) |
| `TrayController` (H.NotifyIcon) | `NSStatusItem` with the same menu |
| `SingleInstance` (mutex + named pipe) | Launch Services already keeps one instance. On a direct binary launch, check `NSRunningApplication` for a running copy and forward the args through `DistributedNotificationCenter` |
| `StartupManager` (registry Run) | `SMAppService.mainApp` |
| `ThemeManager` (registry) | `NSApp.appearance` (System/Light/Dark) |
| `ScreenshotWatcher` (`Pictures\Screenshots`) | Read the `com.apple.screencapture location` setting (fall back to Desktop) and watch it with a `DispatchSource`/FSEvents |
| `AppSettings` JSON | The same field names as `Codable` JSON at `~/Library/Application Support/Sitch/settings.json`, written atomically. Mac defaults for the hotkey and font |
| CLI `--demo*`, `--shot-region=` | Same flags on the binary (`Sitch.app/Contents/MacOS/Sitch --demo`). `--shot-region` is the headless renderer used to check parity |

Milestones, each one buildable and demoable:
- **P2 Core:** model, renderer, effects and tests; `--shot-region` renders the demo document.
- **P3 Editor:** window, tabs, canvas, all 14 tools and their options, undo, crop, zoom, themes, `--demo*`.
- **P4 Capture:**
  - region, window, per-display full screen, recapture, timer, keyboard nudging
  - **Screen Recording onboarding**: check with `CGPreflightScreenCaptureAccess`, request with `CGRequestScreenCaptureAccess`, then the welcome window asks for a relaunch
- **P5 Output:** copy, save in all formats, PDF, share, drag-out, quick capture to clipboard or file.
- **P6 Shell and release:** menu bar, hotkeys, settings window, login item, screenshot watcher, welcome and toast, then **tag v0.2.0**.

## Risks
- **The Screen Recording permission is tied to the code signature.** Ad-hoc rebuilds lose it, the same way they lose Full Disk Access in MacDirStat. Fix: sign local dev builds with `SIGN_IDENTITY` set to the Developer ID so the permission survives rebuilds.
- **macOS 15+ may ask users to re-confirm Screen Recording** from time to time for apps that use ScreenCaptureKit directly. Check how this behaves on 15 and 26. All we can do is document it in the README.
- **SDK mismatch:** local SwiftPM builds use a different SDK than CI's macOS 26. MacDirStat's v0.1.0 crashed only when built in CI. The smoke test and test builds made by CI cover this, as MacDirStat's CLAUDE.md notes.
- **The Windows exe is still unsigned.** Signing it (e.g. with Azure Trusted Signing) is a separate, optional follow-up.
- **GPL and clean-room rules apply to the Mac code too:** no code from ShareX, Greenshot or Flameshot, and nothing taken from the iSkitch binary.

## Verification
- **Phase 0:**
  - `dotnet build windows/Sitch/Sitch.csproj` passes, both locally and in CI's Windows job.
  - On a Windows machine:
    - Start with an existing `%APPDATA%\WinSitch\settings.json` and confirm it migrates.
    - Confirm the `WinSitch` Run entry is replaced.
    - Run `--demo` and check it renders unchanged.
- **Phase 1:**
  - `codesign --verify --strict --verbose=2 Sitch.app`
  - `spctl --assess --type execute -vv Sitch.app` reports `source=Notarized Developer ID`.
  - `xcrun stapler validate Sitch.app`
  - The `v0.2.0-rc1` pre-release has all three assets and opens cleanly after download.
- **Phases 2–6:**
  - `swift test` passes.
  - A `--shot-region` render of the demo document matches the Windows render by eye: effects order, arrow heads, text halo.
  - Real captures on a Retina display plus a 1x external display check the pixel/point math.
  - Pasting into Preview, Slack and Mail checks the clipboard.
  - AirDrop/Mail through the share picker checks sharing.
