# WinSitch

Free, offline, MIT-licensed screenshot-annotation tool for Windows — a native Skitch replacement
(clean-room clone of macOS iSkitch). Tray-resident: global hotkey → capture (region / window /
full screen) → editor → annotate with 14 vector tools → copy / save / drag / share. Privacy-first:
no accounts, no network, no telemetry.

**Docs to consult (don't duplicate them here):**
- `docs/ARCHITECTURE.md` — module map + the invariants the code upholds. **Read it before
  changing capture/DPI, the annotation/render pipeline, or clipboard/share.**
- `docs/SPEC.md` — *what* to build (feature spec, 14-tool rail order, design tokens, shortcuts).
- `docs/PLAN.md` — *why/how* (stack choice, architecture, milestones, risk register, license rules).
- SPEC/PLAN are design intent; the shipped code intentionally deviates in places (e.g. single-Esc
  cancel, editor tabs, remembered window size). **When they disagree, the code is the truth.**

## Stack
- .NET 10 WPF, C#, TFM `net10.0-windows10.0.19041.0`, x64. Windows 10 1903+ / 11.
- Single project, **no `.sln`** — always target `src/WinSitch/WinSitch.csproj`.
- Only two NuGet deps: `H.NotifyIcon.Wpf` (tray) and `PDFsharp-wpf` (PDF). All Win32 P/Invoke is
  hand-written in `src/WinSitch/Capture/Native.cs` — there is no CsWin32.

## Build / run / publish
- Build: `dotnet build src/WinSitch/WinSitch.csproj`
- Run from source: `dotnet run --project src/WinSitch/WinSitch.csproj` (app args go after `--`)
- Release single-file exe (needs **both** flags — single-file/ReadyToRun apply only in Release,
  self-contained only with `-r`):
  `dotnet publish src/WinSitch/WinSitch.csproj -c Release -r win-x64 -o publish` → `publish/WinSitch.exe`

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
- File-scoped namespaces (`namespace WinSitch.Xxx;`), one primary public type per file with
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
  `%APPDATA%\WinSitch\settings.json`, atomic tmp+move, best-effort (errors swallowed).

## Testing
- **There is no test project.** Verify a change by building and driving the app: `--demo*` for
  editor UI, a real capture for the overlay. There is no unit-test harness to run — don't claim
  "tests pass"; say what you actually exercised.

## Versioning & release (manual — no CI)
- The version lives in **four** places that must move together: `WinSitch.csproj` `<Version>`,
  `app.manifest` `assemblyIdentity version`, `Shell/TrayController.cs` About string, and
  `Editor/SettingsWindow.xaml` footer. Features ship as a patch bump in the 0.1.x line.
- Cut a release: bump those four, commit, then publish the exe and
  `gh release create vX.Y.Z --target main --title "WinSitch X.Y.Z" --notes-file <notes> "publish/WinSitch.exe#WinSitch.exe"`.
  The README download link is `releases/latest/download/WinSitch.exe`, so the new release just has
  to be "Latest". The binary is unsigned (SmartScreen warns on first run).

## Guardrails
- **Clean-room / GPL:** ShareX, Greenshot, Flameshot are GPL — reference their architecture, never
  copy or port their code. Reuse only MIT-compatible sources.
- Never bind `Win+Shift+S` (the OS owns it; `RegisterHotKey` fails). Default hotkey `Ctrl+Alt+4`.
- Solo repo: commits go directly to `main`, no PR flow. Commit or push only when asked.
