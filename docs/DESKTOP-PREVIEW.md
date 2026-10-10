# Desktop preview

This is the developer preview of the Windows WPF desktop. It is not a public installer or signed release. The repository currently has no downloadable binary release; see `docs/DESKTOP-INSTALLATION.md` for the packaged-preview workflow when a package is available.

## Requirements

- Windows x64
- PowerShell 7
- .NET SDK version pinned in `global.json` (currently 10.0.401)

The launcher prefers `.tools/dotnet/dotnet.exe` when present. Otherwise it uses `dotnet` from `PATH` and checks that the selected SDK exactly matches `global.json`. It does not install tools, change `PATH`, build the app, or download files.

## Build and open the preview

From the project root in PowerShell:

```powershell
$dotnet = if (Test-Path '.\.tools\dotnet\dotnet.exe') { '.\.tools\dotnet\dotnet.exe' } else { 'dotnet' }
& $dotnet restore '.\RouterStudio.slnx' --locked-mode
if ($LASTEXITCODE -ne 0) { throw 'Restore failed.' }
& $dotnet build '.\src\RouterStudio.Desktop\RouterStudio.Desktop.csproj' --configuration Release --no-restore
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
.\Desktop-Preview.cmd
```

You can also open **Desktop-Preview.cmd** after building. It starts the compiled application without rebuilding it. To build a distributable package, use the maintainer packaging workflow; `Install-Desktop.cmd` is intended for a prepared release package, not a source checkout.

## Product behavior and limits

The preview includes the local dashboard, confirmed management operations, the explicitly acknowledged Test Lab, safe local history/export, and tray controls. Read the [user guide](USER-GUIDE.md), [desktop bridge](DESKTOP-BRIDGE.md), and [management contract](MANAGEMENT-CONTRACT.md) before changing those boundaries.

Configured connection/model and local router reachability do not prove upstream authentication, model availability, or successful generation. Live provider checks can send upstream requests and may incur charges; automated CI uses local/unit fixtures and does not perform paid-provider tests.

Current desktop verification and release gates are documented in [acceptance results](DESKTOP-ACCEPTANCE-RESULTS.md) and [release acceptance](RELEASE-ACCEPTANCE.md).
