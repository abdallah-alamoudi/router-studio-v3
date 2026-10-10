# Task 2 results: management contract

Date: 2026-10-06
Status: Complete for the authorized Task 2 scope. Tasks 3–12 remain unimplemented.

## What changed

The existing management worker now returns a versioned result with controlled error codes and messages. The current UI sends versioned payloads and reads the new results; legacy flat requests remain compatible. Ambiguous or invalid payloads are refused.

Status preserves existing fields and adds runtime versions, declared reasoning levels, a snapshot digest, and separate reachability/configuration-current indicators. The digest uses length-framed exact configuration, catalog and encrypted-store bytes; no plaintext-key digest is persisted.

Interrupted key/provider recovery preserves a durable restart reminder. A reachable router alone cannot clear it. The launcher must acknowledge the matching configuration and marker after confirming that its own child owns the healthy listener. Failed startup retains committed key changes and reports a controlled error.

Explicit fixture arguments isolate installation/configuration paths and local health endpoints. Requests cannot supply these arguments. Redirects are refused. Raw child output is discarded to prevent sensitive error text from entering logs/results.

Fresh setup prepares its generated catalog before launching the router; Codex configuration is still committed after startup. The forwarding engine was not changed.

## Verification

All final commands exited 0:

- `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/worker-contract.ps1`: **26 checks, zero failures**.
- `npm test`: **68 tests passed**, zero failures/skips.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/verification/Verify-Desktop.ps1 -RequireIntegration`: **68 Node tests, 13 parsed PowerShell files, 44 unique XAML names, 13 isolated worker assertions**. The occupied default-port check was explicitly skipped; its listener was preserved.

The contract suite is included in the 68 Node tests, rather than an additional 26 Node tests. It checks actual UI functions with fixture controls, real worker/launcher composition, both current and legacy Windows PowerShell launcher hosts, malformed requests, digest framing, locking, redirects, controlled startup failures, and interrupted recovery.

Initial contract failures and targeted regressions were observed before their fixes. Evidence is retained under `.superpowers/sdd/2026-10-05-router-studio-desktop/task-2/`, including contract-red.txt, fresh-red.txt, review-red.txt, review-green.txt, payload-red.txt, payload-green.txt, contract-final.txt, node-final.txt and verification-final.txt.

## Independent review

One read-only reviewer identified three supported findings, all fixed with failing-then-passing regression tests and the complete suite:

1. Fresh setup lacked the generated catalog before digest-dependent startup.
2. An isolated worker failed to forward its fixture root/health URI to the real launcher.
3. Provider recovery could lose its restart reminder if the worker stopped immediately after transaction removal.

No minor findings were deferred. No second review was substituted for regression verification.

## Scope and decisions

- Shared Studio-Protocol.ps1 centralizes safe errors, request normalization, digest and restart markers. Cost if wrong: every distribution path must include one additional script; copy lists were updated.
- Durable restart markers require matching startup proof. Cost if wrong: conservative reminders may persist until a verified launch.
- Explicit process arguments and scoped fixture mutexes isolate tests. Cost if wrong: an incomplete fixture invocation could reach defaults; tests always provide the isolated root/configuration together and fixture installation is refused.
- Existing catalog preparation writes its validated output before startup. Cost if wrong: a preparatory file can remain after failure; original Codex configuration remains intact until the existing commit stage.
- Legacy Windows PowerShell startup links remain supported. Cost if wrong: old links could fail; both launcher hosts were tested.
- Raw child output is discarded. Cost: less troubleshooting detail; controlled messages remain available.
- C# bridge, DPAPI jobs, cancellation and abandoned-job handling stay in Task 3. Cost of deferral: no claim that these future features exist.
- Probe stale-state UI/history and upstream/SSE bounds stay in Tasks 5 and 7–10. Cost of deferral: snapshot identity exists, but a Test Lab does not.
- Public packaging/signing and complete upgrade-interruption acceptance stay in Task 12. Cost of deferral: this is not a distributable-release certification.
- OS certification/native WPF acceptance stay in later acceptance work. Cost of deferral: fixture UI functions were checked, rendered native screens were not.
- An alleged lifetime-mutex handoff race was unconfirmed. No speculative retries were added; controlled startup failure retains saved keys. Cost if wrong: a user may need another explicit start.
- Versioned payloads are normalized while legacy flat requests remain accepted. Cost if wrong: caller compatibility; both formats and invalid combinations were regression-tested.
- There is no Git repository. Work stays in place with baseline copies/hashes and logs; no commit or PR was fabricated. Cost: no Git rollback/history until a repository is established.

## Files

Existing product files changed: Studio-Worker.ps1, Studio.ps1, Setup.ps1, run-router.ps1 and codex-config.mjs. Baseline hashes confirm the other 20 tracked-in-the-baseline root files are unchanged.

Added Studio-Protocol.ps1, tests/worker-contract.ps1 and tests/worker-contract.test.mjs; adapted tests/worker-integration.ps1 to explicit fixture arguments. Updated README, contract documentation, plan/spec status and execution records.

See [management contract](MANAGEMENT-CONTRACT.md) and [implementation plan](superpowers/plans/2026-10-05-router-studio-desktop.md).

The installed application and live configuration were not updated. No GUI launch, upstream provider request, dependency installation, .NET scaffolding or Task 3 implementation was performed. Full clean-machine installation and upgrade acceptance remain unverified.
