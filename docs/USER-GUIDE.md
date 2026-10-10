# How to use Router Studio

Router Studio manages your local Codex connection, saved gateway keys and model routes. This build is an **unsigned Windows x64 preview**. Public signing and clean-machine acceptance are still pending. Use the latest verified ZIP listed in DESKTOP-ACCEPTANCE-RESULTS.md; keep its checksum and original ZIP for recovery.

## 1. Install and open

1. Save your work. Close Codex and Router Studio. If upgrading, first right-click the Router Studio icon beside the Windows clock, choose **Review router stop**, and confirm. The icon may be under the hidden-icons arrow.
2. Extract the **entire ZIP** into a new folder. Do not run files inside the ZIP or mix files from different releases.
3. Open the extracted folder and double-click **Install-Desktop.cmd**. Read the unsigned-preview notice, then type **INSTALL** if you accept it. The installer uses this Windows account and needs no administrator rights. It does not close applications for you.
4. Press **Win+R**, paste `%LOCALAPPDATA%\RouterStudio\Launch-Desktop.vbs`, and press Enter.
5. Click **Refresh locally**. This reads local settings and router status; it sends no gateway request.

The package includes its own runtimes. You do not need to install Node, PowerShell 7 or .NET separately. Installation itself does not enter keys, change Codex's provider or run generation tests.

## 2. Choose the right starting point

**Already used Router Studio v3 on this Windows account?** Your encrypted keys, routes and backups are reused. Skip first-time setup. If the router is stopped, open **Diagnostics** (F8), choose **Review router start**, read the preview and confirm.

**New user?** First-time setup connects Codex to the gateway and starts the local router:

1. Save work and close Codex.
2. Open **Settings → First-time router setup**.
3. Paste your Plus/default gateway key into the masked field. Pro and Full keys are optional. Enter keys only in the app; do not put them in support messages or screenshots.
4. Click **Review first-time setup**, read the changes and confirm.
5. Sign out of Windows and back in once, then reopen Codex. This lets Codex inherit the local authentication setting.

Setup refuses an occupied router port or conflicting state. On failure, refresh and read Diagnostics before trying another change. Do not run first-time setup over an existing installation to repair it.

## 3. Understand the dashboard

| What you see | What it tells you |
|---|---|
| Configured connection/model | Saved settings; an already open Codex session may still use earlier settings. |
| Router reachable | The local service responded. It does not prove the gateway key or model works. |
| Authentication: Not verified | Sign-in, subscription, quota and upstream access have not been established. |
| Missing key | A model has no usable saved assignment in the local configuration. |
| Out of date / review needed | Refresh or resolve the displayed conflict before making changes. |

Dashboard and Connections refresh locally while visible and idle. Hidden/minimized windows and ongoing actions pause refresh. A test result can become stale after settings change; repeat its preview before another Run.

## 4. Select official access or the router

1. Save work and close Codex.
2. Open **Connections** (Alt+2).
3. Choose **Review official selection** for ChatGPT sign-in, or **Review router selection** for your saved gateway route.
4. Read the preview. Cancel makes no change; confirm applies the selection.
5. Reopen Codex and start a new session. For official access, use official sign-in to select the intended account/workspace.

Changing the default connection does not prove account access or move an existing chat to a different provider. Account quotas are not combined.

## 5. Add a key and assign models

1. Create a key in the intended gateway group first. A label such as CHINESE does not change the key's upstream permissions.
2. Save work and close Codex. Open **Keys** (Alt+4).
3. Enter a saved label. Select the exact raw models to assign; use Ctrl-click for several. Custom labels require a model selection. PLUS, PRO and FULL also support their preset behavior.
4. Choose **Preview assignments** and check the models and label.
5. Paste the key into the masked field, review the apply confirmation and confirm. The key is encrypted for this Windows user and the owned router restarts to load it. Other mappings remain intact.
6. Reopen Codex. Use **Models & routes** (Alt+3) to search models, presets and saved assignments.

The password field clears after submission, including cancellation. If the preview expires or settings change, refresh and preview again. Catalog-declared reasoning levels do not prove gateway support.

## 6. Check locally without paid requests

1. Open **Test Lab** (Alt+5).
2. Select **Local router health**, or **Official configuration (authentication unverified)**.
3. Click **Preview target**, read its scope, check the acknowledgement and click **Run one check**. These two checks make no upstream request.
4. Read the observed result. Local health checks the router; official configuration checks saved settings only.

For this acceptance run, **only local and fixture tests were authorized and performed**. Opening any page does not run a test. **Saved key: model catalog** contacts the gateway. Generation, streaming and synthetic tool checks can incur charges; use them only when you choose to do so. They use a separate preview and acknowledgement, one request, a 30-second deadline and no retries/fallbacks. The generation output cap must be a number from 256 through 2048; it does not cap total cost. Cancel requests cancellation; it cannot undo upstream work or charges. The synthetic tool check validates a reply and never executes a tool.

## 7. Restore a backup

1. Save work and close Codex.
2. Open **Backups** (Alt+6), select a backup and preview its changes.
3. Review restore carefully: it replaces the **whole Codex configuration**, including unrelated preferences saved in that backup. Keys and model catalogs are retained.
4. Confirm, then reopen Codex. Changed current settings or a changed backup invalidate the preview.

Externally edited settings may cause restore to refuse. Keep those edits and inspect the conflict; do not delete ownership/recovery files to bypass the guard.

## 8. Use the tray, startup and support controls

- Right-click the tray icon to open Studio, review router start/stop, or **Exit Studio (keep router running)**. Closing Studio does not stop the router.
- In **Settings**, enable **Close window to tray** if you want the window hidden when closed. Use the tray's Exit action to quit afterward.
- Startup is optional and requires packaged installation. Studio startup and router startup are separate choices.
- If a legacy startup launcher exists, the app preserves it and refuses a duplicate. Press Win+R, open `shell:startup`, and inspect `Safe8stokenRouter.vbs`. To migrate it, move that file to a backup folder **outside Startup**, then enable router startup in Settings. Keep the original for recovery.
- Settings also offers saved themes, history clearing and **Export safe support details**. Local history retains up to 200 records for 30 days, excluding keys, request/response bodies and ordinary proxy traffic. Review any exported file before sharing it.
- Shortcuts: Alt+1–7 selects pages; Ctrl+R refreshes; F8 toggles Diagnostics; Escape closes Diagnostics; Tab moves focus.

## 9. Upgrade or uninstall

**Upgrade:** stop the router through its tray review, exit Studio, close Codex, extract the new ZIP and repeat installation. The installer verifies files and preserves user data. An unchanged owned launcher helper upgrades automatically. External edits cause a refusal. On an interrupted upgrade, rerun the same installer to recover before opening Studio. Keep the previous ZIP.

**Uninstall:** first decide how Codex should connect afterward. Select official access or restore an appropriate direct-connection backup while Studio is still installed. Stop the router, exit Studio and close Codex. If `shell:startup` contains a legacy router launcher, move it to a backup folder outside Startup before removing runtimes; that legacy file is retained by uninstall.

Open Windows PowerShell in the extracted package folder and run:

```powershell
.\scripts\Uninstall-Desktop.ps1 -Acknowledge
```

To also remove verified versioned application/runtime files:

```powershell
.\scripts\Uninstall-Desktop.ps1 -Acknowledge -RemoveRecoveryFiles
```

Uninstall deactivates the desktop, removes matching owned startup registry entries and restores matching prior engine files. It preserves Codex provider settings, encrypted keys, router settings, history and recovery preimages. Edited or incomplete releases are kept for review. It does not wipe user data or automatically restore Codex. Reinstalling the retained ZIP can reactivate the preview.

## 10. Common problems

| Problem | Next step |
|---|---|
| Window will not open | Verify full extraction and checksum; run the installer from the complete package. Confirm it is Windows x64. |
| Installer says a router is running | Save work, stop the router through Studio, and exit Studio. Retry; no process is forcibly closed. |
| Port is occupied | Keep the existing listener intact. Identify its owner before starting another router. |
| Disabled changes / stale preview | Refresh locally, read Diagnostics and create a new preview. |
| Key store cannot be opened | Use the same Windows account and computer that created it. Do not copy encrypted keys between accounts. |
| External edit / recovery refusal | Keep your edited files and original ZIPs; inspect the conflict before replacing anything. |
| Router healthy but model fails | Local health does not prove model access. Check the saved assignment and upstream permissions; a live test is a separate choice. |
| Codex still uses earlier settings | Close and reopen Codex; start a new session. After first-time setup, sign out/in to Windows once. |

For current verification and remaining limits, read DESKTOP-ACCEPTANCE-RESULTS.md and RELEASE-ACCEPTANCE.md.
