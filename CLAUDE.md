# Sitch

Free, offline, MIT-licensed screenshot-annotation tool — a native Skitch replacement (clean-room
clone of macOS iSkitch). Tray-resident: global hotkey → capture (region / window / full screen) →
editor → annotate with 14 vector tools → copy / save / drag / share. Privacy-first: no accounts,
no network, no telemetry. Formerly **WinSitch**; persisted names migrate on first run (see
`SettingsStore.Load`, `StartupManager.MigrateLegacy`).

**Two apps, one repo.** `windows/` is the shipping .NET/WPF app and the reference implementation;
`mac/` is the native Swift port in progress (its own `mac/CLAUDE.md`; roadmap and C# → Swift
mapping in `docs/MACOS_PORT.md`). Stack through Conventions below describe the Windows app;
Versioning & release and Guardrails cover both.

**Docs to consult (don't duplicate them here):**
- `docs/ARCHITECTURE.md` — module map + the invariants the code upholds. **Read it before
  changing capture/DPI, the annotation/render pipeline, or clipboard/share.**
- `docs/SPEC.md` — *what* to build (feature spec, 14-tool rail order, design tokens, shortcuts).
- `docs/PLAN.md` — *why/how* (stack choice, architecture, milestones, risk register, license rules).
- SPEC/PLAN are design intent; the shipped code intentionally deviates in places (e.g. single-Esc
  cancel, editor tabs, remembered window size). **When they disagree, the code is the truth.**

## Stack
- .NET 10 WPF, C#, TFM `net10.0-windows10.0.19041.0`, x64. Windows 10 1903+ / 11.
- Single project, **no `.sln`** — always target `windows/Sitch/Sitch.csproj`.
- Only two NuGet deps: `H.NotifyIcon.Wpf` (tray) and `PDFsharp-wpf` (PDF). All Win32 P/Invoke is
  hand-written in `windows/Sitch/Capture/Native.cs` — there is no CsWin32.

## Build / run / publish
- Build: `dotnet build windows/Sitch/Sitch.csproj`
- Run from source: `dotnet run --project windows/Sitch/Sitch.csproj` (app args go after `--`)
- Release single-file exe (needs **both** flags — single-file/ReadyToRun apply only in Release,
  self-contained only with `-r`):
  `dotnet publish windows/Sitch/Sitch.csproj -c Release -r win-x64 -o publish` → `publish/Sitch.exe`
- On macOS the project **compiles** (not runs) with `-p:EnableWindowsTargeting=true` — enough to
  catch build breaks; driving the app still needs Windows.

## CLI flags (verify behavior without a real screen capture)
- `--demo` / `--demo-crop` / `--demo-light` — open the editor on a synthetic dashboard with
  annotations pre-placed (these generate the README screenshots).
- `--settings`, `--capture`, or a bare file path (opens that image).
- `--shot-region=<path>` — headless render-and-exit; skips the single-instance mutex.
- A second launch **forwards its args to the already-running tray instance** over a named pipe, so
  `--demo` opens nothing if an instance is running. Quit the tray app first to test a fresh launch.

## Architecture must-knows (full detail in `docs/ARCHITECTURE.md`)
- **Two coordinate spaces — never mix them.** `Capture/` is *physical virtual-screen pixels*
  (freeze-frame BitBlt, one topmost overlay per monitor, selection math in physical coords).
  `Core/` + `Editor/` are *document pixels*, converting to DIP only for on-screen layout. This is
  why mixed-DPI multi-monitor capture is correct — changes in `Capture/` are high-risk.
- **Non-destructive annotations.** The pristine capture is immutable; every mark (incl.
  obscure/spotlight) is an editable object in an ordered list. `Core/Renderer.cs` composites
  `base → obscure effects → spotlight dim → vector marks` — effects flatten BEFORE shapes so
  blur/pixelate never smears an arrow. Redactions flatten to pixels only at export.
- **Tray-resident.** `ShutdownMode=OnExplicitShutdown` (App.xaml): closing all editors does NOT
  quit; the app stays in the tray. Quit runs `App.QuitRequested()` (prompts dirty tabs).
- **Single instance** (`Shell/SingleInstance.cs`) and **theming** (`App.xaml`
  `MergedDictionaries[0]` is the swappable active theme, replaced by `ThemeManager`).

## Conventions
- File-scoped namespaces (`namespace Sitch.Xxx;`), one primary public type per file with
  colocated helper records/enums. `Nullable` + `ImplicitUsings` on; `sealed` leaf classes; modern
  C# (target-typed `new`, `[...]` collection expressions, pattern matching, records, `required`).
- **UI is mostly code-built, not XAML.** Only `EditorWindow` and `SettingsWindow` have `.xaml`; the
  rail, swatches, pickers, toasts, welcome and countdown are built in C#. Tool glyphs are
  `Geometry.Parse` path data in `Editor/ToolIcons.cs` whose brush binds to the host's `Foreground`
  (theme + selection tint flow automatically). Match this when adding toolbar icons.
- **Comments:** terse single-line "why" notes (rationale/edge cases, not restating code);
  `/// <summary>` on public/internal classes carries the design rationale. Many cite upstream
  parity (`v1.3`, `v1.4.0`, `v1.5 parity`) → `docs/SPEC.md`.
- **Settings:** mutate the static `App.Settings`, then `SettingsStore.Save(App.Settings)`. JSON at
  `%APPDATA%\Sitch\settings.json`, atomic tmp+move, best-effort (errors swallowed).

## Testing
- **There is no test project.** Verify a change by building and driving the app: `--demo*` for
  editor UI, a real capture for the overlay. There is no unit-test harness to run — don't claim
  "tests pass"; say what you actually exercised.

## Versioning & release (tag-driven CI, both platforms)
- One version line for both apps. On Windows it lives in **four** places that must move together:
  `Sitch.csproj` `<Version>`, `app.manifest` `assemblyIdentity version`, `Shell/TrayController.cs`
  About string, and `Editor/SettingsWindow.xaml` footer. The Mac app takes it from the tag.
- Cut a release: bump those four, commit, push, then push a tag `vX.Y.Z`.
  `.github/workflows/release.yml` fails fast if the four stamps don't match the tag, builds
  `Sitch.exe` (windows-latest) and a signed, notarized `Sitch-macOS.zip` (macos-26), and publishes
  both in ONE release — the platforms share "Latest", so a release missing either asset would
  break that platform's `releases/latest/download/…` link. It also attaches the exe as
  `WinSitch.exe`, the name the README and older links download. `vX.Y.Z-rcN` tags publish as
  pre-releases (never Latest) — use one to dry-run the pipeline.
- Secrets (same names as MacDirStat): `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`,
  `NOTARY_API_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`. The Windows exe is unsigned
  (SmartScreen warns on first run).

## Guardrails
- **Clean-room / GPL:** ShareX, Greenshot, Flameshot are GPL — reference their architecture, never
  copy or port their code. Reuse only MIT-compatible sources.
- Never bind `Win+Shift+S` (the OS owns it; `RegisterHotKey` fails). Default hotkey `Ctrl+Alt+4`.
- Solo repo: commits go directly to `main`, no PR flow. Commit or push only when asked.
