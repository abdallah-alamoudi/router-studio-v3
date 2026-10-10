# Contributing

Thanks for helping improve Router Studio. Changes should preserve the project's local-first behavior, explicit confirmations for configuration changes, and clear separation between local health and upstream provider access.

## Before opening a pull request

1. Open an issue first for large behavior changes so the user impact and safety boundaries can be discussed.
2. Keep changes focused. Do not add dependencies or background network behavior without a concrete need and a documented reason.
3. Run the checks relevant to your changes on Windows:

   ```powershell
   npm test
   dotnet restore RouterStudio.slnx --locked-mode
   dotnet build src/RouterStudio.Desktop/RouterStudio.Desktop.csproj --configuration Release --no-restore
   dotnet test tests/RouterStudio.Core.Tests/RouterStudio.Core.Tests.csproj --configuration Release --no-restore
   ```

4. Describe what changed, why, tests run, and any checks not run. For UI changes, include screenshots and note the Windows version/scaling used.
5. Never include credentials, personal configuration, local build output, release ZIPs, or user data in a change.

## Tests and provider safety

CI runs Node.js tests, builds the WPF desktop, and runs .NET Core unit tests on Windows. The interactive desktop acceptance executable and live-provider checks are intentionally not run in CI. Do not use a paid provider or real user profile for ordinary tests. Any live upstream test must be separately authorized and explicitly described because it can send requests or incur charges.

## Pull requests

Keep the title concise and user-oriented. Link related issues, document compatibility or migration impacts, and call out changes to installer/package behavior. Do not claim a release is ready based only on unit tests; use the release acceptance documents.
