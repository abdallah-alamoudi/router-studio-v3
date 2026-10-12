# Remaining desktop release acceptance

The automated host/fixture checks do not establish public readiness. Record the release ZIP SHA256, Windows build, account type, test steps, observed result and evidence for each check. Never use real keys in acceptance fixtures. Paid provider testing is skipped by the user's explicit choice.

## Offline clean environment

On a machine with Windows Sandbox enabled, generate a configuration from the extracted verified package:

```powershell
.\scripts\New-DesktopSandbox.ps1 -PackageRoot 'C:\releases\1.0.0-preview.11' -OutputPath 'C:\tests\router-offline.wsb'
```

Open that .wsb file. The package appears at `C:\RouterStudioPackage`, read-only; networking and clipboard sharing are disabled. Copy it to a guest-local folder before testing if you need writable extraction. Run Install-Desktop.cmd in the guest, then open `%LOCALAPPDATA%\RouterStudio\Launch-Desktop.vbs`. Verify opening, navigation, theme, missing-setup states, local refresh and ordinary exit without downloads. Do not enter keys. Photograph or record results before closing the disposable guest.

The generator only creates XML; it does not enable Windows features or launch a VM. [Microsoft documents networking and read-only mapped folders](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file). Sandbox uses its own account and is **not standard-user acceptance**. Use a dedicated Windows VM with a standard account for the full gate:

1. Begin with no separately installed Node, PowerShell 7 or .NET, and networking disabled.
2. Install/open the verified package as a standard user without elevation. Record runtime/PATH state before and after.
3. Seed only synthetic local data, retain its hashes, install a previous verified release, then upgrade to the new release. Verify retained settings/keys and active pointer.
4. Run the repository's `tests\migration.ps1` and `tests\installation-entrypoints.ps1` locally inside the VM for interruption/tamper/external-edit fixtures. These use temp roots and do not establish real-profile migration on their own.
5. Test actual-profile uninstall both with startup disabled and after enabling owned startup. Confirm that unrelated startup entries and synthetic user data remain. Remove any legacy launcher from Startup before runtime cleanup, as described in USER-GUIDE.md.
6. Reinstall and verify recovery. Repeat on Windows 10 before claiming Windows 10 support. Sandbox on a Windows 11 host does not prove Windows 10 compatibility.

## Second Windows account

This helper uses a random **synthetic** CurrentUser DPAPI payload, never the application's key store. [CurrentUser protection is tied to user credentials](https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.protecteddata?view=netframework-4.8).

Under account A, use a new folder:

```powershell
.\scripts\Test-SecondUserEncryption.ps1 -Action Prepare -FixtureRoot 'C:\tests\router-dpapi-A'
```

Keep the printed SHA256 separately. Copy the two synthetic files and helper script to a location readable by account B, without changing file bytes. Sign in as account B on the **same machine**, then run:

```powershell
.\Test-SecondUserEncryption.ps1 -Action Verify -FixtureRoot 'C:\tests\router-dpapi-A' -ExpectedSha256 '<hash printed by A>'
```

Exit 0/PASS means account B could read the intact ciphertext but DPAPI refused decryption. Exit 1/FAIL means it decrypted successfully. Exit 3/BLOCKED means same account, changed bytes, unreadable files or invalid setup; those outcomes cannot count as isolation. Verify owner metadata against account A's recorded SID. Delete only the synthetic fixture afterward. No account creation or password collection is performed.

Separately test the application's wrong-owner install refusal using synthetic configuration on another account; this helper alone does not prove every key-store migration path.

## Physical Windows UI

With a human tester, check 100%, 150% and 200% Windows display scaling at a 960×640 window; restart the app when changing display scaling. Navigate all seven pages, scroll to every action and check readable wrapping/focus. Use only the keyboard for navigation, preview, cancellation, diagnostics, local checks and normal close. Use Narrator to verify names, states, errors and result announcements. Check Windows high contrast and saved System/Light/Dark themes. Record clipping, focus loss or inaccessible controls as FAIL.

For startup/tray, in a disposable VM: enable each startup option separately, sign out/in, verify exactly one intended process, open via tray, close to tray, reopen and exit while preserving the router. Confirm an unrelated startup entry remains unchanged. Automated rendered DPI screenshots and single-instance fixtures cannot replace this check.

## Public signing

Public release is BLOCKED until there is an approved signing identity and a signed distribution design. The current installer explicitly refuses signed mode. Do not use a self-signed certificate to claim public publisher trust. When inputs exist, implement signed package/wrapper verification, timestamp validation, unsigned/tampered refusal before side effects, and rerun clean-machine upgrade/uninstall with the actual signed artifact. Current full-file hashes detect alteration; they are not publisher authentication. No distribution/publication is authorized by this acceptance pass.
