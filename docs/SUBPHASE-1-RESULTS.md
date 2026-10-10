# Subphase 1 results

Date: 2026-10-05
Scope: Task 1 of `superpowers/plans/2026-10-05-router-studio-desktop.md`.
Status: PASS for the automated Windows baseline. Tasks 2-12 are not implemented.

## What changed

- `tests/switch.test.mjs`: use fileURLToPath for CLI launches; exercise spaces and non-ASCII characters; prove negative CLI cases fail for the intended refusal rather than a missing module.
- `tests/health-fixture.mjs`: authenticated localhost-only fixture with dynamic-port readiness.
- `tests/worker-integration.ps1`: hidden quoted fixture launch, occupied-port preflight, isolated temporary user data/fake keys, 13 preserved assertions, owned-process and directory cleanup.
- `tests/tooling.test.mjs` and `tests/helpers/run-process.mjs`: behavioral verification-tool regressions, including failing checks, honest skips, correct working directory, and timeout process-tree cleanup.
- `tools/verification/Verify-Desktop.ps1`: repeatable Node, PowerShell, XAML, and worker checks; nonzero failures; explicit integration eligibility/result.
- `README.md`: current verification instructions and limits.

## Verified evidence

Environment: Windows, Node 24.21.0, PowerShell 7.6.6.

| Requirement | Result / evidence |
| --- | --- |
| Windows CLI baseline reproduced | Original switcher suite: 18/21; three CLI launch failures. `switch-red.txt` records the path regression before correction. |
| CLI path and intended refusal regressions | Final switcher suite: 22/22 within the full suite. |
| Full Node suite | `npm test`: 67/67, zero failures/skips, exit 0 (`node-final.txt`). |
| Complete verifier | `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/verification/Verify-Desktop.ps1 -RequireIntegration`: exit 0 (`verification-final.txt`, `verification-exit.txt`). |
| PowerShell parse | 11 current source/test/tool files; zero parse errors. |
| Embedded XAML | Well-formed XML, 44 unique named controls. |
| Occupied port | Fixed port 18761 explicitly SKIP. Sentinel regression proves an unrelated listener remains responsive. |
| Worker assertions | 13/13 using an OS-assigned port, fake keys and isolated user data. |
| Independent review finding | Timeout could orphan a fixture. Reproduced in `timeout-red.txt`; tree termination now passes in the full Node suite and verifier. |
| Product behavior preserved | All 25 root product/script/manifest hashes match the pre-change baseline. |

Evidence logs and original test snapshots are retained under
`.superpowers/sdd/2026-10-05-router-studio-desktop/`.

## Decisions and limits

1. This folder has no Git repository. Baseline copies and SHA256 hashes provide local comparison evidence; no commit or branch was created. Git-based rollback is unavailable.
2. Instead of stopping the router to free port 18761, isolated worker checks adapt only the health URL and mutex in a temporary worker copy. This verifies worker behavior without proving the occupied fixed endpoint works. The fixed-port skip is explicit.
3. Windows process-tree termination is denied inside the restricted sandbox. Final checks ran with permission to terminate test-owned trees. Cleanup failure is reported as failure, never as success; the confirmed leftover from the diagnostic run was removed.
4. Local evidence is retained because there is no Git history to replace it. No dependency installation, installed-config mutation, live-provider request, or public release was performed.

Native WPF rendering/accessibility, installation/upgrade, cross-user encryption denial, and live provider/model tests remain unverified and belong to later subphases.

Next planned subphase: Task 2, management contract versioning/hardening. It requires separate authorization; this result does not start it.
