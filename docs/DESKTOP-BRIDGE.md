# Desktop worker bridge

Task 3 adds RouterStudio.Core, a Windows-targeted .NET 10 library without a UI framework dependency, management server, database or upstream test engine. The existing PowerShell UI remains available.

## Build

global.json pins SDK 10.0.401. This workspace has a Microsoft SHA512/signature-verified copy under .tools/dotnet. That ignored folder is a local tool, not part of the app distribution. Another checkout needs the matching [official SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0).

From PowerShell 7 in the project folder:

~~~powershell
$taskDotnet = Join-Path (Get-Location) '.tools/dotnet/dotnet.exe'
& $taskDotnet restore RouterStudio.slnx --locked-mode
& $taskDotnet test RouterStudio.slnx --no-restore
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/verification/Verify-Desktop.ps1 -RequireIntegration
~~~

NuGet.Config allows only nuget.org and uses a project-local cache. Each project has packages.lock.json. Directory.Build.props enables nullable analysis, warning failures, lock generation and transitive dependency audits. The verifier uses locked restore and disables SDK/test-platform telemetry for its child build.

Core's only package is System.Security.Cryptography.ProtectedData 10.0.12. Tests use Microsoft.NET.Test.Sdk 18.10.1 and matching MSTest.TestFramework/TestAdapter 4.4.1. Pinned direct packages and their signatures were inspected before execution; all 14 resolved package signatures were subsequently verified. The source folder has no Git repository.

## Calls and contracts

IStudioBackend exposes ExecuteAsync(StudioRequest, SecretInput?, CancellationToken) and GetSnapshotAsync(CancellationToken). Requests use schemaVersion=1, an action, and a nonsecret payload. Results carry data or a controlled StudioError. Snapshots have typed connection, router health, models, credential labels, backups, runtimes, digest and timestamp. Failed snapshots throw StudioBackendException carrying a controlled error.

Core checks schema/action, exact payload field names, duplicate fields, label/model/backup syntax, boolean acknowledgement, lengths and probe bounds before creating a job or launching a process. Production probes return unsupported_capability without a launch. Probe DTOs and a dedicated-process seam support later Task 7; no paid request is implemented here.

WorkerBackendOptions supplies trusted absolute local executable/script paths. FixturePaths explicitly overrides installation root, configuration path and a strictly validated loopback health URI. Those process arguments never come from request payloads. Launch uses ProcessStartInfo.ArgumentList, UseShellExecute=false and CreateNoWindow=true.

Each backend accepts one operation at a time. An exclusive bridge.lock serializes separate backend instances/processes sharing the job root. The worker's existing management mutex still serializes legacy callers and installation changes.

## Secret path

SecretInput owns a copy of UTF-8 action-specific JSON bytes. Save-key uses {label,key}; the encrypted label must match the public label. Installation uses {PLUS,PRO,FULL}, with required PLUS and optional empty PRO/FULL. Public payloads reject keys.

JobSecretWriter uses Windows DPAPI CurrentUser and null optional entropy, writing only secret.dpapi. It clears its temporary plaintext byte copy. Disposing SecretInput clears its owned bytes. Callers must clear their source bytes and password controls promptly.

The worker decrypts in memory, validates the shape, constructs SecureStrings and deletes secret.dpapi even on rejection. Save-key passes the SecureString directly to existing storage. Installation adapts SecureStrings to the existing current-user encrypted initial-keys.xml interface; this additional encrypted envelope is removed in finally. Legacy encrypted XML jobs remain accepted; mixed formats are refused.

No plaintext JSON file or key command-line argument is written. JSON parsing still creates managed strings; this does not promise perfect memory erasure. DPAPI/ACLs protect against other ordinary users, not same-user malware or administrators.

## Jobs, results and cancellation

UUID jobs live under LocalAppData/RouterStudioJobs. Its protected ACL grants only the current Windows SID and SYSTEM; jobs inherit it. Root links are refused and linked job trees are preserved.

owner.json records creation time and owner/worker PID plus start time. PID reuse does not prove a live owner. The worker holds active.lock through completion. Core removes its own completed job on success/failure. Cleanup errors conservatively retain data in the restricted root.

Core drains stdout/stderr into Stream.Null. It waits for worker exit before reading result.json, checks exit status, result size <=4 MiB, JSON depth <=32, schema and shape, then maps error codes locally. Early/partial results are never accepted.

Reads/probes may be cancelled; only the app-created process handle/tree is terminated. Mutations ignore cancellation after launch and are awaited to their final result. Cancellation before launch prevents the action. Parent exit does not automatically terminate a mutation worker.

Status can perform legacy recovery. The worker holds commit.lock before recovery writes. A cancelled read must acquire that same exclusive lock before termination; if recovery owns it, Core waits for the final result.

CleanAbandonedJobs is an explicit startup-maintenance method for Task 4 shell composition. It takes the bridge lock and removes only UUID jobs older than 24 hours with absent owner/worker and no active/commit lease. It preserves recent jobs, live processes, unknown/corrupt metadata, linked trees and non-job directories. Legacy jobs without ownership metadata are kept.

Known deferred minor: an inaccessible/disappearing job can abort the sweep because some inspection precedes the per-job catch. No deletion follows that error. The future shell must treat startup maintenance as best-effort and handle IO/permission errors; moving those checks inside the guarded region is tracked for follow-up.

## Verification and pending acceptance

Tests use temporary installation/configuration paths, fake keys and local process fixtures. They include real Core-to-worker snapshots/key commits, C# ciphertext-to-PowerShell decryption, malformed inputs/results, active/abandoned jobs, cross-instance serialization, cancellation and recovery locks. Installed configuration, live router and upstream providers are untouched.

On 2026-10-06, the user explicitly left second-Windows-user DPAPI acceptance pending. Current-user success is not evidence of wrong-user denial.

To run that separate acceptance check:

1. In an isolated creator account, create a fake-key CurrentUser DPAPI blob and record its SID. Use a temporary shared test folder solely for this acceptance check; production jobs must stay private.
2. Under a different isolated account, run:

~~~powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/dpapi-envelope.ps1 -VerifyWrongUser -CipherFile <fake-ciphertext-path> -CreatorSid <creator-SID>
~~~

3. The script refuses the creator SID and succeeds only on a CryptographicException from decryption. Delete isolated test data afterwards.

No account was created or account credentials requested. Native WPF rendering, clean-machine installation, provider probes and public release acceptance remain later tasks.
