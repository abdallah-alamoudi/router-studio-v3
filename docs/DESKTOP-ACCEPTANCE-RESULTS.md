# Desktop acceptance follow-up — 2026-10-09

This pass fixes five reproduced defects and documents everyday use. Channel remains **unsigned-preview**; public release remains **BLOCKED** on external acceptance and signing. User authorized **local and fixture tests only**. No paid provider requests, real-profile installation, startup changes or publication were performed.

## Changes

- Invalid visible Test Lab token input now disables Preview/Run and is checked by their handlers. Previously the numeric binding retained the last valid value while buttons stayed enabled. Native regression verifies disabled controls, no request and recovery after correction.
- An upgrade can replace stable helper files only when their bytes match the fully verified active release. External edits are refused. Installation holds the management mutex through bootstrap and payload changes; ordinary failures restore bootstrap preimages. Helpers retain the existing pointer/schema contract for interrupted installs.
- Uninstall now reads absent optional startup values without a Windows PowerShell 5.1 exception. Actual installer/uninstaller entry-point fixtures cover first install, upgrade, failure recovery, retained data and repeated uninstall without enabled startup.
- Reinstall now recognizes restored/deleted control files after uninstall, while retaining original recovery preimages and refusing later external edits. Independent review found stale ownership hashes blocking reactivation; restored-engine fixtures pass in both PowerShell versions.
- Output caps apply only to generation/streaming/tool checks. Switching from an invalid numeric model cap to local, official-configuration or catalog checks no longer traps Preview with a disabled input field. Nonmodel requests use the default harmless cap value.
- USER-GUIDE.md covers install, existing/new setup, connections, key assignments, local checks, backups, tray, upgrades, uninstall and troubleshooting. Outdated preview descriptions were corrected.
- New-DesktopSandbox.ps1 creates an offline read-only package mapping without launching a VM. Test-SecondUserEncryption.ps1 prepares/verifies a random synthetic DPAPI fixture, rejects same-account/tampered setup and requires an independently retained hash.

## Evidence

Evidence folder: `.superpowers/sdd/2026-10-09-desktop-acceptance/`. RED failures are retained separately from passing checks. The original verified preview.7 remains available as baseline evidence. Preview.8 is historical and predates independent key/custom-model management. The current feature-bearing unsigned preview and its validation are recorded in the final section below; do not install an artifact without its adjacent checksum and validation report.

The fresh full verifier exited 0. Windows PowerShell 5.1 migration also passed separately.

| Check | Result |
|---|---|
| Node policy/protocol/tooling regression | PASS — 99 |
| C# contracts, lifecycle, bridge and view models | PASS — 77 |
| Native WPF fixture | PASS — 92, plus isolated entry-point/single-instance lifecycle |
| Actual Windows PowerShell 5.1 installer entry points | PASS — 22, synthetic payload/profile |
| Migration, interruption, external edits and reinstall | PASS — 31 under PS7 and PS5 |
| Current-user encrypted envelopes | PASS — 21 |
| Second-user helper false-positive regressions | PASS — 3; actual second-account test remains unverified |
| Isolated worker integration | PASS — 13 |
| PowerShell syntax and XAML | PASS |
| Fixed port 18761 | SKIP — occupied listener preserved; isolated worker port passed |
| NuGet direct/transitive advisory query | PASS — exit 0, no reported vulnerable packages |

The second-user regressions exercise helper verdicts under the current account; they do **not** claim a real second-account test. Initial failed runs are retained, including the verifier-fixture integration defect corrected before the fresh passing run. Source literal-key/private-key pattern scanning found zero suspect files in its stated scope; it is not exhaustive proof of secret absence. No Git history was available for scanning. Package verification and archive SHA256 are recorded separately so they can describe the final archive without changing it.

## Remaining limits

- No accessible VM commands or usable signing tools/certificate were found during this pass. Clean standard-user/no-runtime install, actual-profile offline upgrade/uninstall, Windows 10 and signing remain unverified.
- No second-account credentials/environment were available. Actual second-user DPAPI/key-store acceptance remains unverified.
- Physical keyboard/Narrator/DPI/high-contrast and sign-in startup/tray acceptance still need a human tester. Rendered images and native fixtures alone do not prove these outcomes.
- Legacy Startup-folder router launchers remain a manual migration/removal step. Move the reviewed legacy launcher outside Startup before deleting private runtimes. Uninstall preserves Codex's provider configuration; select official access or restore an appropriate backup beforehand.
- Paid provider acceptance is skipped by user choice. Local health/configuration checks cannot prove upstream authentication, quota or model access.

Follow RELEASE-ACCEPTANCE.md for the external gates. Do not describe this artifact as signed or public-ready.

## Historical archive verification — preview.8 (2026-10-09)

Publisher exited 0. Final preview.8 package validation passed **16/16**, including self-contained open/second-instance/normal close in an isolated empty root with runtime PATH removed. The bundled private PowerShell and Node also passed **13/13** isolated worker checks. This is host fixture evidence, not clean-machine acceptance.

ZIP size: 222,039,348 bytes. SHA256: `4ac4f28cbc88bd75c08bb5a33a4e7fe226aada38fa255096115b26a5a9153337`. Its `.zip.sha256` and `.zip.validation.txt` files are adjacent to the archive. The source version of this report includes post-build results; the immutable packaged copy directs readers to the separate validation report. The archive was not modified after validation.

## Independent keys and Custom Models — preview.11 (2026-10-12)

The feature-bearing package is an unsigned offline preview built from the current local feature branch. It contains the independent saved-credential and Custom Model UI/worker/router flows, updated user guide and management contract. See the adjacent `1.0.0-preview.11.zip.validation.txt` and `.zip.sha256` for package-specific evidence and identity. Full source verification on 2026-10-12: Node 140/140, Core 97/97, native WPF acceptance 108 checks, Windows PowerShell 5.1 installer entrypoints 22 checks, migration fixtures 31 checks, current-user DPAPI 21 checks, isolated worker integration 13 assertions; `Verify-Desktop.ps1 -RequireIntegration` exited 0. Package validation passed 18 checks, including extracted manifest verification, runtime signatures/versions, required management modules/docs, hash check and isolated open/second-instance/normal-close without runtime PATH. Port 18761 was occupied and preserved; isolated worker integration passed on an OS-assigned port.

This is not a signed/public final release. Clean-machine/standard-user install, real second-account DPAPI test, physical accessibility/DPI, Windows 10, live provider compatibility and paid generation were not tested. No real credentials or Codex configuration changes were used, and no installation/publication was performed.