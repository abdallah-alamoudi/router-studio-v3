# Router Studio

[![CI](https://github.com/abdallah-alamoudi/router-studio-v3/actions/workflows/ci.yml/badge.svg)](https://github.com/abdallah-alamoudi/router-studio-v3/actions/workflows/ci.yml)

Router Studio is a Windows desktop control panel and local router for Codex-compatible workflows. The desktop is built with WPF/.NET; routing and provider configuration use Node.js, with a PowerShell worker for Windows integration.

> **Preview status:** this repository currently publishes source code, not a ready-to-install binary release. The desktop/package is an unsigned preview and some release acceptance checks remain open. Do not treat it as a signed or production-supported installer.

## Run from source (Windows)

### Requirements

- Windows x64
- Node.js 22 or later
- .NET SDK **10.0.401**, pinned by [`global.json`](global.json)
- PowerShell 7 to launch the desktop preview

Install those tools using their official installers. The repository does not silently download an SDK or alter your system `PATH`.

### Build and launch

```powershell
npm test

dotnet restore RouterStudio.slnx --locked-mode
dotnet build src/RouterStudio.Desktop/RouterStudio.Desktop.csproj --configuration Release --no-restore

.\Desktop-Preview.cmd
```

If the pinned SDK is already in `.tools/dotnet/dotnet.exe`, the preview launcher uses it; otherwise it uses `dotnet` from `PATH` and verifies that it resolves the version in `global.json`. The launcher starts the existing build; it does not build or download anything.

To run the Core unit tests after restore:

```powershell
dotnet test tests/RouterStudio.Core.Tests/RouterStudio.Core.Tests.csproj --configuration Release --no-restore
```

For the full local verification tool and its optional isolated worker checks, see [Desktop bridge and verification](docs/DESKTOP-BRIDGE.md). Do not run live provider/generation tests unless you deliberately choose to: they can send upstream requests or incur charges.

## Installing a packaged preview

When a packaged build is published, download its complete ZIP from the repository's **Releases** page, extract the whole archive, then run `Install-Desktop.cmd` and follow its confirmation prompts. **Do not run the source-tree installer expecting it to build the app**; the installer is for a prepared release package. There is no public binary release yet.

The end-user workflow and safeguards are documented in the [user guide](docs/USER-GUIDE.md) and [desktop installation guide](docs/DESKTOP-INSTALLATION.md). Package and release limitations are recorded in [acceptance results](docs/DESKTOP-ACCEPTANCE-RESULTS.md) and [release acceptance](docs/RELEASE-ACCEPTANCE.md).

## Project map

- `src/router/` — Node.js router and provider/configuration modules
- `src/worker/` — PowerShell worker and Windows integration
- `src/RouterStudio.Core/` — shared .NET application logic
- `src/RouterStudio.Desktop/` — native WPF desktop application
- `tests/` — Node.js and .NET tests
- `tools/` — packaging, installation, and verification utilities
- `docs/` — user, architecture, and release documentation

See [management contract](docs/MANAGEMENT-CONTRACT.md) for the local management protocol and [desktop bridge](docs/DESKTOP-BRIDGE.md) for the .NET/worker boundary.

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Please report security vulnerabilities privately using GitHub's **Report a vulnerability** action rather than filing a public issue; see [SECURITY.md](SECURITY.md).

This project is distributed under the [MIT License](LICENSE).
