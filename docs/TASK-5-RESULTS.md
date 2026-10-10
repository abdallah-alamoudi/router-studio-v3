# Task 5 — Dashboard and truthful connection state

Implementation verified for the authorized scope on 2026-10-06. Physical Windows display scaling and human accessibility acceptance remain pending. This is still a developer preview.

## Delivered

- Dashboard consumes typed worker snapshots: configured connection/model, authentication explicitly unverified, separate local-router reachability and loaded-configuration state, review/catalog status, local timestamps and runtime versions.
- Counts distinguish catalog models, explicit catalog routes (presets/exact mappings), saved key labels and catalog models missing a saved key. Counts stay hidden until a successful read.
- Local refresh every 15 seconds on visible Dashboard/Connections pages while idle, plus manual refresh. Hidden/minimized windows, other pages, running actions and modal confirmations suspend refresh eligibility; reads cannot overlap.
- Connection selection uses the existing official/router worker operations with a review dialog defaulting to Cancel. Router confirmation supplies the saved-work/closed-Codex acknowledgement required for a possible restart.
- Restart/new-session guidance remains across navigation and refreshes for the current app session. It also appears after failed selection attempts because a worker can commit before its status/startup step fails. No detection of existing Codex session configuration is claimed.
- Failed refresh/mutation makes prior status out of date and disables switching until a successful local read. Review conflicts also block switching. Probe composition invalidates earlier results after digest changes or failed reads; Test Lab/history remain later tasks.

No new dependencies or configuration store. Existing management, encrypted storage and recovery mechanisms remain in use. No installed settings or real credentials were changed by verification; no upstream requests were sent.

## Verification

| Surface | Result |
| --- | --- |
| Node suite | 74/74 pass, zero skips |
| Core, bridge and presentation suite | 53/53 pass, zero skips |
| Current-user DPAPI | 21 checks pass |
| Native WPF fixture | 50 checks pass; actual entry-point smoke also passes |
| Worker integration | 13 checks pass on an OS-assigned port |
| PowerShell syntax / legacy XAML | 18 files parsed / 44 unique names validated |
| Native locked build | Zero warnings/errors |
| Full desktop verifier | Exit 0 |

The occupied fixed port18761 was safely skipped; the existing listener was untouched. Tests include actual worker-to-Core explicit-route metadata, real visible-window timer ticks and minimization, confirm/cancel action routing, review/missing-catalog fixtures, stale and unknown states, safe failures, scrolling and native bindings.

RED/GREEN: eleven composer/presentation assertions failed before implementation; actual worker explicit-route assertion failed before the metadata addition; native configured-model assertion failed before view binding. The final count-availability adjustment also has a failing assertion and a fresh complete C# suite/native build and fixture run after the change.

The first restricted native restore failed because official NuGet advisory data could not be reached. The same locked build passed with network access; package checks were not disabled. This is not a new dependency intake or a full release security audit.

Independent read-only review found no actionable findings. Its excluded features (history, full management parity and production Test Lab) belong to later tasks. A separate executor check hid unknown counts instead of displaying guessed zero.

## Limits and decisions

Native96/144/192DPI images were visually inspected, including page bottoms at192DPI. These rendered images do not verify physical Windows100/150/200% display scaling. Human keyboard/screen-reader use, real Windows high contrast/theme transitions, separate-account acceptance, real installed connection changes and upstream access remain unverified.

No Git repository exists. Changes are kept in place with baseline copies and local logs; no commit or branch was created. Deleting local evidence would lose the only change record, so it is retained.

The existing design and user request to implement the next task authorize Task5 only. Tasks6–12 remain gated; they were not implemented here.

## Try it

Double-click Desktop-Preview.cmd, then use Refresh locally or wait for the visible-page timer. Read [the preview guide](DESKTOP-PREVIEW.md) before applying connection changes. Task6 (management parity) is next.

Evidence: .superpowers/sdd/2026-10-05-router-studio-desktop/task-5 (baseline, RED/GREEN, full verifier, fresh final Core/native logs, screenshots and review).
