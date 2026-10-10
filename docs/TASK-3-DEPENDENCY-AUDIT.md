# Task 3 dependency and secret audit

Date: 2026-10-06. Surface: new .NET bridge build/source dependencies and test artifacts, not a public release.

| Surface | Verdict | Evidence and limits |
|---|---|---|
| SDK provenance | PASS | Official Microsoft release metadata for 10.0.401; downloaded ZIP SHA512 matches; dotnet.exe Authenticode valid, Microsoft signer. sdk-provenance.json and sdk-signature.json. |
| Package intake | PASS | ProtectedData and MSTest/Test SDK identities, nuspec/build targets inspected before restore; direct package author/repository signatures verified. package-signatures.txt. |
| Resolved signatures | PASS | All 14 downloaded direct/transitive NuGet packages verified, exit 0. transitive-signatures.txt. |
| Advisory scan | PASS | NuGet current advisory source reports no vulnerable packages in Core or tests, including transitive packages; exit 0. dependency-audit.txt. This is an advisory result for this date, not proof of absence of vulnerabilities. |
| Reproducibility | PASS | global.json pins SDK; fixed direct versions; package lockfiles record resolved versions/content hashes; locked restore passed. |
| Test/result canaries | PASS | No fake-key canary in Task 3 log/JSON/TRX artifacts at pre-review scan; request/argument/result scans and job-deletion assertions run in tests. Fake constants deliberately exist in test source. |
| Public release | Not evaluated | No packaging/signing/distribution was performed; release audit remains Task 12. |

Aggregate for available Task 3 build/source surfaces: PASS. Git-history coverage is unavailable. Second-user DPAPI runtime acceptance is separately pending at the user's request; dependency audit does not establish that boundary.

Evidence directory: .superpowers/sdd/2026-10-05-router-studio-desktop/task-3/.
