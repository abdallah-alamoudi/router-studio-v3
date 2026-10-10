# Management contract v1

Task 2 supplies the PowerShell management boundary for the future desktop bridge. It does not implement the C# bridge or live model probes.

## Requests and results

Current UI requests use a versioned envelope with nonsecret action details:

~~~json
{"schemaVersion":1,"action":"save-key","payload":{"label":"CHINESE","ids":["deepseek-v4.1-flash"],"ack":true}}
~~~

Legacy flat requests remain accepted. Mixing legacy fields (ack, label, ids, id) with payload, or supplying a non-object payload, is refused. Restart/restore acknowledgement must be boolean true. Supported actions remain install, status, official, router, start, repair, restore, save-key.

Keys still arrive in legacy encrypted CLIXML job envelopes (key.xml, initial-keys.xml); Task 3 will add the proposed DPAPI envelope. The worker removes these envelopes in finally.

Success: `{schemaVersion:1, ok:true, data:{...}}`.
Failure: `{schemaVersion:1, ok:false, error:{code,message}}`.

Messages come exclusively from GetStudioError in Studio-Protocol.ps1; arbitrary exception/child error text is not returned. Codes include invalid_request, unsupported_schema, acknowledgement_required, invalid_key, installation_incomplete, installation_failed, endpoint_override, config_changed, busy, recovery_required, startup_failed, operation_failed. The fallback UI resolves display text by code locally.

## Status compatibility

Existing fields stay: connection, healthy, models, keys, backups, message.

Additional fields: runtimeVersions.node, runtimeVersions.powershell, snapshotDigest, checkedAtUtc, restartRequired, and routerHealth (reachable, configurationCurrent). Model rows add supportedReasoningLevels, derived only from catalog effort metadata; missing metadata remains an empty array.

Reachability and loaded configuration are separate. configurationCurrent requires a matching launcher acknowledgement; an older router without one remains unverified.

## Snapshot bytes and recovery

Digest = lowercase SHA256 of these files, in this exact order:

1. router-config.json
2. codex-router-catalog.json
3. encrypted secrets.xml

Each file contributes its unsigned 64-bit big-endian byte length followed by its exact bytes. No plaintext-key digest is stored. Unrelated logs/state files are excluded. A second digest check rejects status if these inputs changed while composing it.

Legacy key/provider transaction formats are retained. Before recovery starts, the worker persists studio-restart-required.json with a unique marker ID. That reminder survives another worker or interruption. Missing key backups report recovery_required.

The launcher writes router-loaded-snapshot.json only after authenticated, nonredirecting local health succeeds, the listener belongs to its own Node process, and the saved digest still matches. It records the recovery marker ID seen before loading credentials. The worker clears a reminder only when health, marker ID and digest all match; older startup records cannot clear newer recovery.

Key updates remain serialized and require acknowledgement. If startup fails after commit, the encrypted key/routes remain saved and restart-needed state persists. Status does not imply that recovered credentials are already loaded.

Fresh setup's existing enable-extreme preparation now writes the validated generated catalog before launching the digest-dependent router. Codex configuration and rollback state are still committed only after startup succeeds.

## Fixture boundary

Worker parameters -InstallRoot, -ConfigPath, -HealthUri are explicit process arguments with production defaults. They are never read from request payloads. Always supply isolated temporary root/configuration paths together for tests.

Health accepts only HTTP 127.0.0.1 at /__router/health, without userinfo/query/fragment, and follows no redirects. Test-root mutexes are isolated. A test-mode worker forwards its normalized root and validated URI to its launcher. Fixture install is refused; Setup fixture overrides allow only Status/Upgrade to avoid user startup/environment writes.

The existing 13-check harness invokes the real worker with these parameters and simulates a launcher acknowledgement. The contract suite also exercises real worker/launcher composition and both PowerShell launcher hosts. All use fake keys; no upstream provider request is made.

~~~powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/worker-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/verification/Verify-Desktop.ps1 -RequireIntegration
~~~

npm test includes the contract suite on Windows. Windows inventory/process-tree cleanup need normal permissions; restricted agent sandboxes may deny them. Native WPF rendering, full clean-machine installation, public packaging and live providers remain later acceptance work.
