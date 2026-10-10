# Desktop preview release gate

Current channel: **unsigned-preview**. Public release verdict: **BLOCKED**.
Use USER-GUIDE.md for daily operation, DESKTOP-ACCEPTANCE-RESULTS.md for the latest fixes, and RELEASE-ACCEPTANCE.md for repeatable external checks. Local/fixture testing only was authorized for this acceptance pass; paid tests are skipped by choice.

- Automated checks: Node policy/protocol, C# contracts/view models/history, native WPF fixtures, same-user DPAPI, isolated worker and migration. Exact latest results are recorded in TASKS-8-12-RESULTS.md and the execution evidence folder.
- Runtime provenance: pinned Node, PowerShell and .NET versions; official SHA-256 archives; valid Node/PowerShell executable signatures; include licenses and notices. Update manifest and rerun packaging/audit when patches change.
- Distribution: versioned self-contained app with private runtimes; full-file manifest and archive SHA-256. Hashes do not replace Authenticode or installer signing.
- Required external evidence: clean Windows VM standard-user install with no runtimes, offline launch, upgrade/recovery/uninstall, second account encrypted-store refusal, occupied port and externally edited Codex configuration.
- Required manual UI evidence: keyboard/screen reader, physical DPI/high contrast, tray startup/exit, supported Windows versions including Windows 10 if claimed.
- Required public-release inputs: approved signing identity/certificate and signed installer wrapper; verify signature, timestamp and unsigned refusal; no publishing is authorized.
- Live provider acceptance: opt-in only; one request per selected model/key/probe, record digest and outcome. Official sign-in, authentication and quota cannot be inferred from config/local health. No live paid tests were performed by implementation verification.

Retain failed/skipped logs, recovered artifacts and known limitations. No Git repository is available, so history scanning and commit-based reproducibility cannot be asserted.

Clean-machine uninstall acceptance remains required. The pilot retains recovery files by default and supports explicit removal of verified application/runtime releases while preserving edited releases and user data. Windows PowerShell 5.1 migration has 27 passing isolated checks; it does not replace clean-machine acceptance.
