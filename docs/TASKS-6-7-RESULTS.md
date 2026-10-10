# Tasks 6–7 — Management previews and provider-check backend

Implementation and automated verification passed for the authorized scope on 2026-10-06. Physical Windows scaling, human accessibility and live provider acceptance remain unverified. This is a developer preview.

## Delivered

Task 6 adds model search/filter/details with catalog-declared reasoning levels, saved-key references, encrypted key add/replace with assignment preview, configuration backup preview/restore, and confirmed Diagnostics start/repair actions. Password submission clears the masked field, including cancellation. Confirmations default to Cancel. Existing preset restrictions, unrelated route mappings, restart guidance and transaction recovery remain in use.

Previews perform no configuration writes. Apply guards include encrypted keys, router configuration, catalog, switcher state, Codex configuration and the selected backup where relevant. External changes require a new preview. Backup diffs expose setting names and presence only; authentication, header and arbitrary TOML values are hidden. Restore replaces the full Codex configuration while preserving encrypted keys and catalog bytes.

Task 7 extracts shared route selection with preset > exact > default precedence, preserving the original forwarding behavior and byte-preserving rewrite tests. Known-model resolution and nonsecret probe planning are available for later generation checks. Catalog checks select one saved credential label, require acknowledgement, issue one fixed HTTPS GET to 8stoken, disable redirects/retries, and bound responses to 1 MiB and 30 seconds. The worker passes only the selected key through a dedicated child environment, removes it from launch state immediately after spawning, discards child stderr and maps only safe result fields. Local and official checks send no upstream requests. Official configuration does not establish authentication, workspace access or quota.

Probes refuse pending recovery rather than changing installation files. They leave the production router and configuration intact. Generation, streaming and tool probes remain Task 8; the Test Lab interface remains Task 9. No live provider requests were made during this work.

No dependencies were added. Installation/control copy lists now include the shared modules required by the new router and worker. Production controls resolve beside the executing worker so the source preview uses matching modules without upgrading the installed forwarding process; injectable test fixtures retain isolated module roots. No installation or upgrade was run against real user data.

## Verification

| Surface | Fresh result |
| --- | --- |
| Node suite, including original forwarding regressions | 93/93 pass; zero skips |
| Core, bridge, actual worker and presentation tests | 63/63 pass; zero skips |
| Current-user DPAPI envelopes | 21 checks pass |
| Native WPF fixture | 72 assertions pass; entry-point smoke passes |
| Isolated worker integration | 13 assertions pass |
| PowerShell syntax / legacy XAML | 18 files parsed / 44 unique names validated |
| Native locked build | Zero warnings/errors |
| Full desktop verifier with required integration | Exit 0 |

The existing listener on port 18761 was preserved. Fixed-port integration was explicitly skipped and an OS-assigned fixture port passed instead. Tests used fake keys and isolated configuration, including save/switch/restore, unchanged key/catalog bytes after restore, stale preview refusal, no-write probes, acknowledgement, selected child credential, absent other upstream keys, secret-bearing child output rejection, malformed responses, timeout and cancellation. Typed ProbeRequest defaults were exercised through the actual worker.

RED/GREEN evidence is retained for the missing preview, presentation, native and provider-check behavior. One fresh independent read-only review found no actionable Critical, Important or Minor issues and passed 35 focused Node tests.

An earlier Task 6 full run timed out in the existing 20-second native timer assertion. An unchanged native rerun passed, and the final full run passed after Task 7. The intermittent cause remains unconfirmed; this work does not claim to fix a timer defect. Both failure and rerun evidence are retained.

Native page-top/bottom screenshots at 192 DPI, including the dark key page, were visually inspected for clipping and reachable controls. Rendered images do not prove physical OS scaling, human keyboard/screen-reader behavior, or actual Windows high-contrast transitions. Separate-user DPAPI, live upstream acceptance, installed-user mutation and public packaging remain unverified.

## Try it and next work

Open **Desktop-Preview.cmd**, refresh locally, then use Models & Routes, Keys, Backups or Diagnostics. Follow [the preview guide](DESKTOP-PREVIEW.md) before applying changes. Task 8 is next; Tasks 8–12 were not implemented.

No Git repository exists, so no commit or branch was created. Baseline copies, review, RED/GREEN logs, final exit code and screenshots are retained under `.superpowers/sdd/2026-10-05-router-studio-desktop/tasks-6-7`. Retain this evidence as the local change record.
