# Tasks 8–12 results

Implementation verified on 2026-10-09. Distribution is an **unsigned preview**; public release remains **BLOCKED** on external acceptance and signing.

Task 8 adds fixed synthetic Responses, incremental bounded SSE, and a synthetic tool-argument check. Each explicit test makes at most one gateway request, with no retry, redirect, fallback, tool execution, or second request. Limits are 30 seconds, 1 MiB, and 256–2048 output tokens. Missing/failed/incomplete terminal output cannot pass. Results discard upstream bodies and error text.

Task 9 adds preview, assigned model/key/effort, potential-charge acknowledgement, Run, Cancel, elapsed progress and typed outcomes in Test Lab. Navigation never sends a request. Direct gateway checks and local router health have separate scope; official configuration checks do not establish sign-in or quota.

Task 10 adds restricted per-user history, 200-record/30-day retention in returned and saved records, corruption recovery, clear and allowlisted support export. Keys, payloads, ordinary proxy traffic and arbitrary exception text are excluded. Snapshot changes mark results stale. A null history row regression was reproduced and fixed.

Task 11 adds a single instance per user, tray restore/start/confirmed stop, close-to-tray, safe exit waiting for a mutation, saved theme and separate startup preferences. Legacy startup ownership is retained to avoid duplicates. First-time setup has masked key fields and encrypted job submission. Existing keys require no re-entry. A WPF close-event reentrancy crash was reproduced and fixed; native entry-point close now exits normally.

Task 12 adds a self-contained Windows x64 build, pinned private runtimes, full-file manifest, ZIP checksum, per-user offline installer, version staging, recoverable upgrade journal, atomic replacement, same-user store check, external-edit refusal and conservative deactivation. It changes no global PATH and downloads nothing on launch. Deactivation retains encrypted data, settings, history and recovery releases; it does not automatically restore Codex. A later acceptance pass allows verified owned bootstrap upgrades; external edits are refused. Legacy startup migration is a documented manual step. No Git repository exists, so no commits or Git-history scan are claimed.

## Verified evidence

The full `tools/verification/Verify-Desktop.ps1 -RequireIntegration` run exited 0:

| Check | Result |
|---|---|
| Node regression/policy/protocol | PASS — 99 |
| C# contracts, bridge, view models, history/lifecycle | PASS — 76 |
| Native WPF fixtures and entry-point/single-instance smoke | PASS — 84 plus entry-point smoke |
| Current-user encrypted envelopes | PASS — 21 |
| Isolated migration, interruption, tamper/external-edit checks | PASS — 27 (latest targeted checks; full run had 24) |
| Isolated worker round trip | PASS — 13 |
| PowerShell parsing and XAML names | PASS |
| Fixed port 18761 | SKIP — occupied listener preserved; isolated-port worker passed |
| NuGet direct/transitive vulnerability report | PASS — no reported vulnerable packages in the successful query |

Evidence is under `.superpowers/sdd/2026-10-05-router-studio-desktop/tasks-8-12/`, including RED/GREEN logs, runtime hashes/signatures, native screenshots, full verification and dependency-advisories.json. Restricted-run failures are retained separately from the passing permitted runs. Runtime provenance and licenses are described in runtime-manifest.json and DESKTOP-INSTALLATION.md.

The independent reviewer identified five packaging issues: interrupted staging, torn copies, external control edits, late bootstrap validation and unguarded uninstall. All were corrected, with recheck and migration evidence retained. A further Windows PowerShell 5.1 UTF-8 issue was corrected with explicit encoding. Latest package validation evidence is package-validation.log; archive hashes are beside each versioned ZIP. Earlier preview artifacts are retained for traceability; use the latest verified version.

## Remaining external gates

No live paid provider request or publication was performed. Clean-machine standard-user installation with no existing runtimes, complete offline migration, another Windows account, physical DPI/screen-reader acceptance, Windows 10 support, and a signed installer remain unverified. Automated rendered DPI images and current-user fixtures do not establish those facts. See RELEASE-CHECKLIST.md before distribution beyond the unsigned pilot.

Final post-review checks: Windows PowerShell 5.1 migration27/27PASS and actual worker contracts9/9PASS. Latest rebuilt artifact: artifacts/desktop/win-x64/1.0.0-preview.7.zip. Earlier versions are retained evidence and should not be installed. Explicit -RemoveRecoveryFiles removes verified versioned application/runtime files; externally edited releases and user data are preserved.

Final preview.7 package validation: 14/14PASS, exit0, including private runtime signatures/versions, full manifest, redistribution notices, signed-mode refusal, ZIP hash and self-contained native lifecycle with runtime PATH removed. SHA256: 6e65be9765e13b60b6c4d2acddd482321827481adf294024748ce19d511c2716. Latest migration: 27/27PASS under PS7 and Windows PowerShell5.1. Source/artifact literal-credential scan found zero suspected files in its stated scope; it is not exhaustive proof of secret absence.

These are the Tasks 8–12 baseline results. Read DESKTOP-ACCEPTANCE-RESULTS.md for subsequent fixes and USER-GUIDE.md for current usage.
