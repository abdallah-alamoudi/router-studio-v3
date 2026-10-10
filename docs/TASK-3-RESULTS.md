# Task 3 results: secure bridge and .NET contracts

Date: 2026-10-06
Status: Implemented and verified for the authorized scope. Second-Windows-user DPAPI runtime acceptance remains explicitly pending at the user's request. Task 4 has not started.

## Delivered

- RouterStudio.slnx, a Windows-targeted RouterStudio.Core library, and MSTest project with pinned SDK/packages and lockfiles.
- Versioned request/result and typed snapshot/probe DTOs; IStudioBackend, disposable SecretInput, JobSecretWriter and WorkerBackend.
- Validated process launches using argument lists, hidden windows, trusted fixture overrides and one outstanding action across instances sharing a job root.
- Private UUID jobs restricted to the current Windows SID and SYSTEM. No plaintext key JSON or key arguments; CurrentUser DPAPI ciphertext is decrypted in worker memory and passed to existing SecureString storage.
- Compatibility with legacy encrypted XML inputs. Installation receives the existing PLUS/PRO/FULL fields through a temporary current-user encrypted adapter.
- Controlled malformed-result and worker-exit errors, bounded result reads after child exit, raw output discarded.
- Cancellation for owned read/probe process trees; launched mutations finish. Status-triggered recovery has a shared commit lock so cancellation waits once recovery is writing.
- Abandoned-job maintenance with a 24-hour threshold, process PID/start-time identity checks, independent worker/commit leases and conservative retention of uncertain/linked jobs.
- Complete verification now includes .NET and DPAPI checks. The existing UI remains usable; the forwarding engine is unchanged.

## Final evidence

All final verification commands exited 0:

| Check | Result |
|---|---|
| npm test | 72 passed; zero failed, cancelled or skipped |
| .NET Core suite in Verify-Desktop.ps1 | 37 passed; zero failed or skipped |
| Management contract suite included in Node | 26 checks passed |
| DPAPI/recovery suite included in Node and separately verified | 21 checks passed |
| Legacy isolated worker integration | All 13 assertions passed |
| Source PowerShell parsing | 16 files parsed |
| XAML XML/names | 44 unique names; native rendering not checked |

The occupied default health port was reported SKIP; isolated worker integration passed and the unrelated listener was preserved. Counts of nested checks are coverage counts, not additional Node test cases.

Final command:
~~~powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/verification/Verify-Desktop.ps1 -RequireIntegration
~~~

Evidence is retained under .superpowers/sdd/2026-10-05-router-studio-desktop/task-3/: core-red.txt, additional-red.txt, dpapi-red.txt/dpapi-green.txt, recovery-lease-red.txt, token-limit-red.txt, verifier-red.txt/verifier-green.txt, review-red.txt/review-green.txt, node-final.txt/node-exit.txt and verification-final.txt/verification-exit.txt. Final .NET results are also in TestResults/Core/core-tests.trx.

Tests exercise actual Core-to-worker snapshots/key commits, C# ciphertext-to-PowerShell decryption, fake fixture failures, mutation/read cancellation, cross-instance serialization, ACLs and cleanup. They use fake keys and temporary user/configuration paths. Final log/JSON/TRX artifact scans found no key canary.

## Independent review and fix pass

One read-only independent reviewer found three Important issues. All were reproduced with failing tests, fixed, and passed targeted tests plus the full suite:

1. Typed ProbeRequest serialized using casing/numeric enum/default null fields that the wire validator refused. Shared wire JSON options now use camelCase, snake-case enum names and omit null optionals; every ProbeKind and the injected/production-unavailable paths are covered.
2. Null snapshotDigest escaped as ArgumentNullException. It now returns a controlled invalid_result through StudioBackendException; a subsequent refresh is also checked.
3. Test cleanup reopened numeric PIDs without checking process identity. Fixtures now record start times, and cleanup refuses mismatches. The regression uses a separately owned sentinel, never a user application.

Deferred Minor: inaccessible/disappearing stale-job inspection can abort a cleanup sweep because some inspection precedes the guarded region. No deletion follows that error. Future shell maintenance must handle it as best-effort; moving those checks inside the per-job guard is tracked for follow-up. No Critical finding was supported. No re-review was used in place of regression verification.

## Dependencies and remaining limits

Official SDK 10.0.401 was downloaded to ignored .tools/dotnet, verified against Microsoft's SHA512 metadata and Authenticode signer, and pinned in global.json. Machine SDK/PATH settings were not changed.

The current direct/transitive NuGet advisory audit reports no vulnerable packages; all 14 downloaded packages passed signature verification. See [dependency audit](TASK-3-DEPENDENCY-AUDIT.md). This is not release/security certification.

There is no Git repository. No commit/PR was fabricated; baseline copies/hashes and execution logs remain available. Existing root product changes are limited to Studio-Protocol.ps1 and Studio-Worker.ps1; verification/tests/docs/build scaffolding are additional changes.

Second-user DPAPI runtime denial was not run: the user chose to leave it pending. The supplied check refuses a same-SID run. See [bridge guide](DESKTOP-BRIDGE.md) for the separate-account procedure, build instructions and managed-memory limitations.

No account was created, installed application/configuration updated, live router stopped, GUI launched or upstream provider contacted. There is no native desktop shell or production probe runner yet. Cancellation cannot promise upstream billing cancellation; live tests belong to later tasks.

## Decisions and tradeoffs

- Keep .NET 10 and provision it locally: costs disk space/tool provisioning rather than a machine installation.
- Preserve no-Git baselines: no Git rollback/commit history yet.
- Defer second-user acceptance by explicit user instruction: cross-account runtime evidence remains missing.
- Make read cancellation wait for recovery's commit lock: a cancelled refresh may take time to finish.
- Provide a probe process seam without enabling production probes: Test Lab remains unavailable until its task.
- Reuse encrypted installer input: one extra temporary encrypted file, removed on completion.
- Use process start times and leases; preserve uncertain jobs: some stale jobs need manual review.
- Discard raw output and cancel pipe drains after exit: less troubleshooting detail, with controlled results available.
- Require .NET verification when Core exists: SDK prerequisites cannot be silently skipped.
- Reaffirm the pending second-user acceptance after review: no wrong-user pass claim.
- Defer upstream/SSE/tool bounds and stale-result/history UI to Tasks 7-8 and 5/10: those future guarantees are not claimed.
- Defer native UI, password-control clearing and alternate CODEX_HOME UI enforcement: the bridge is not a finished desktop caller.
- Defer signing, upgrade interruption and clean-machine distribution to Task 12: no release certification.
- Same-user malware/admin access and perfect managed-string erasure are outside DPAPI guarantees: credentials may be accessible to those actors/in process memory.
- Exclude cosmetic preferences from this correctness pass: formatting can be improved separately.

Next planned task: Task 4, native shell and design system. No Task 4 implementation was performed.
