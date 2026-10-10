# Task 4 — Native shell and design system

Status: implementation verified for the authorized shell scope. Manual environment acceptance remains pending. This is a UI preview, not a finished everyday-use app.

## Delivered

- Native WPF window with Dashboard, Connections, Models & Routes, Keys, Test Lab, Backups and Settings.
- Local status header, explicit local refresh, safe diagnostics that reflow the page and leave focused controls visible.
- Light/dark/system appearance, system-color high contrast palette, color tokens and an 8px spacing rhythm, flexible scrolling at minimum960x640, visible focus and keyboard shortcuts.
- Reusable loading, empty, error and confirmation controls; confirmation defaults to Cancel.
- UI-independent shell state and commands linked into Core tests, preserving IStudioBackend.
- Native fixture acceptance, actual entry-point smoke, compiled preview launcher and beginner preview guide.

The functional pages clearly state what is coming next. Only manual local refresh reaches the backend from this UI; no mutation control or live provider test is exposed. Theme choice is session-only. No new configuration store or UI/MVVM package was added. Existing scripted UI and forwarding engine are unchanged.

## Fresh verification — 2026-10-06

| Surface | Evidence |
| --- | --- |
| Node suite | 74/74 pass, zero skips |
| C# Core + shell tests | 41/41 pass (includes four new shell regressions) |
| Native WPF fixture | 35 assertions pass |
| Actual desktop entry point | Empty fixture root, native window opens and exits normally |
| Current-user DPAPI | 21 assertions pass |
| Worker integration | 13 assertions pass on OS-assigned port |
| PowerShell syntax | 18 files parsed |
| Legacy XAML structural check | 44 unique names; native rendering separately tested |
| Solution/native build | Zero warnings and errors |
| NuGet advisory query | Four projects checked, no vulnerable packages reported by official feed |

The fixed health port was occupied and safely skipped; isolated integration passed on another port. No installed configuration or real credentials were changed by acceptance; no upstream requests were made. Build and checks used project-local .NET10.0.401 and PowerShell7.

Regression sequence: four shell assertion failures -> four passes; native theme resource, selector contrast and window backdrop failures -> native passes. Two final Important review findings were reproduced and fixed once: stale native binaries and invisible focus behind diagnostics. The full verifier then passed. Native acceptance now performs a fresh locked build; it does not depend on dotnet test building non-test executables.

## Review and limits

Independent read-only review found two Important issues (fixed and regression-tested) and one Minor issue (deferred): View safe details toggles an already-open diagnostics drawer closed. The header/F8/close controls remain usable.

Pending: separate-account runtime check, real OS display scaling, human keyboard/screen-reader checks and Windows high contrast/theme transitions. Native screenshots were rendered at96/144/192DPI and visually inspected; they do not establish OS display scaling. Real installed-setup refresh remains a later acceptance check, because the existing worker may perform transaction recovery during status reads.

Dependency intake: PASS for this change's package/build surface. Native APIs come from the verified Microsoft SDK; no new external package was introduced. Locked restore and official advisory query succeeded. This scoped result is not a full release security audit.

## Use and next step

Double-click Desktop-Preview.cmd in the project folder. See [preview guide](DESKTOP-PREVIEW.md) and [acceptance evidence](desktop-acceptance.md). Task5, the actual dashboard and truthful connection state, is next; it is not implemented here.

At the ready-to-use milestone, deliver the requested full beginner guide for installation, connection selection, credentials, model routes, explicit tests and backup/recovery, with a worked example. Packaging and daily-use journeys still belong to later tasks.

Evidence: .superpowers/sdd/2026-10-05-router-studio-desktop/task-4. Baselines, review, RED/GREEN logs, final verification, native JSON and package audit remain local because this project has no Git history.
