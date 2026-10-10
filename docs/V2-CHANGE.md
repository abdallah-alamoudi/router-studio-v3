v2 change

Approved scope: a Windows menu switching the existing local Codex connection
between official ChatGPT subscription access and the 8stoken router, plus
extra raw model key mappings and missing-Codex-selector diagnostics.

Implementation: provider-switch.mjs edits managed root fields and preserves
other tables. State stores each provider's model choices. A journal recovers
interrupted writes. Menu.ps1 requires manually closing the app. Diagnose.ps1
collects app/version information and selected nonsecret configuration only.
Manage-Models.ps1 adds DPAPI-encrypted credentials and modelRoutes.

No subscription pooling, account token storage, model protocol conversion,
quota dashboard, hidden-feature enabling, or automatic request retries.
