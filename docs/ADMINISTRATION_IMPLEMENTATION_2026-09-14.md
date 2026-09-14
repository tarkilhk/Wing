# Administration implementation — 14 September 2026

The Flutter administration screens now use the corrected Studio navigation:
Profile, Server and Health. This is an implementation and host-validation record,
not Android release acceptance or a claim that every backend contract is complete.
The [design handoff](design/2026-09-14-administration-handoff.md),
[scope audit](research/ADMINISTRATION_SCOPE_AUDIT_2026-09-14.md) and
[provider-source correction](research/PROVIDER_CREDENTIAL_SOURCE_RECHECK_2026-09-14.md)
define the boundaries below.

## Delivered client behavior

Profile has six drill-downs: Defaults, Identity, Memory, Skills and tools, Access
and connectors, and Behavior. Server has Connection, Providers, Profiles and
Runtime. Health separates runtime observations from selected-profile usage and
diagnostics. The selected server is visible throughout. Detailed inventories and
forms stay below the tab roots. Settings search identifies the owner and opens
the owning editor. Missing profile selection does not remove Server or runtime
Health actions. Missing runtime identity is shown explicitly with retry.

Shared provider accounts explicitly target the discovered canonical `default`
root. Profile access describes effective sources and explicit overrides. Saved
connection credentials remain device-held connection details. They do not change
the server password. Composer gesture preferences moved to device Settings below
appearance and text-size controls.

The shared `hermes_theme.dart` and `profile_workspace_theme.dart`, together with
their token assertions, are reconciled from the delivered Studio PR #14 sources
at `c588a746569d7ea985a11ea131f4c3ce03acdb62` (merged as
`2f27227107ab97f360bd1371beb8aa544539555a`). This checkout initially predated that
delivery. Administration now inherits the complete application theme rather than
overriding a subset of colors and button states. Existing dirty markdown and
composer code was not replaced by the Studio branch.
The existing model picker also receives the delivered 14sp explanatory text and
shared field radius, keeping its controls above a 320dp phone's keyboard.

| Roadmap | Implemented surface | Boundary |
| --- | --- | --- |
| A01–A02 | Existing main-model editor; capability-gated reasoning and speed defaults | Defaults apply to new sessions. Model identity is rechecked before reasoning/speed saves. Unsupported flags do not create controls. |
| A03–A06 | Existing individual skill/tool toggles and inventories, reached from Skills and tools | Configured, enabled and platform remain distinct. Toolset enablement can start backend setup; it is not proof of readiness. |
| A07 | Searchable retained-memory list and complete detail | Read-only; generated positional identity is used only for reads. |
| A08 | Explicit unavailable state | Edit/delete requires a stable identity and concurrency-safe backend contract. No memory mutation is sent. |
| A09–A11 | Shared and profile access inventories, source labels, stored-key management, supported device-code sign-in, cancellation, disconnect | External CLI login remains external. Pool-account detail cannot be safely attributed to an arbitrary selected owner; it is explicitly unavailable. No credential values are fetched for display. |
| A13 | Auxiliary assignments, automatic choice, reset-all, unavailable-model warning, expensive-model confirmation | Reset-all discloses endpoint-credential clearing. Readback must match the affected tasks. |
| A14 | Ordered fallback list with add/remove/reorder, schema-supported agent/subagent execution controls | Fallback edits check for an already-changed list and verify the saved result. Custom provider definitions remain P2. |
| A16 | Existing description/SOUL editor under Identity | Uses the captured profile gateway; existing readback behavior is retained. |
| A17 | Create, clone configuration, rename and delete under Server / Profiles | Default profile has presentation-only rename and no delete action. Creation/rename/deletion is followed by discovery. Unconfirmed outcomes remain unconfirmed. Full-data/channel cloning and optional multi-step setup are not offered. |
| A18–A19 | Recorded skill usage ordering, provenance, complete instructions, edit/archive agent-owned skills | Bundled instructions are read-only. Existing changed content is detected before saving; this is not a server compare-and-swap guarantee. |
| A20 | Official Hub/search, provenance preview, install, uninstall and group update | Tracks returned background action identity and actual exit status. No install/update was executed on the user's server during implementation. |
| A22 | Scoped toolset providers, effective key readiness, model selection, explicit post-setup action | Setup explains host requirements and tracks the returned action. An effective inherited key is not offered as removable from the profile. |
| A24–A25 | MCP inventory/enablement, cached status, explicit Test, returned tool details and prompt/resource counts, browser OAuth, remove; global reload under Server / Runtime | Per-tool edits remain unavailable because the backend replaces the whole map. Missing cached status is not disconnected. OAuth uses the configured server callback. Runtime reload is process-wide. |
| A27 | Agent-plugin inventory/status and individual enablement | Selected P1 portion only. Install/remove/update and Desktop UI extensions are outside this slice. |
| A28 | Memory enablement and character budgets | Exact retained-file sizes lack an arbitrary-profile contract and are explicitly unavailable. |
| A31 | Basic compression enablement, threshold, target and protected recent messages | Schema-supported basic controls only; advanced context-engine work remains P2. |
| A32 | Approval mode/timeout, command allowlist, reload confirmation | Backend policy is distinct from per-chat controls. |
| A33 | Secret redaction, private-URL access and checkpoint enablement | Uses `security.allow_private_urls`; browser-profile grants and advanced recovery remain P2. |
| A36–A37 | Existing connection management and authenticated profile diagnostics | Device connection settings and backend policy remain separate. |
| A38–A39 | Bounded log categories/severity/search; explicit Doctor and security audit with action status | Runtime scope is independent of mobile selection. No automatic repair or new restart action. |
| A41 | Existing backend version and eligible-update flow under Runtime | No backend update was executed. |
| A42 | Rolling 1/7/30/90/365-day usage with per-model sessions, calls, tokens and estimated cost | Hermes estimates, not provider invoices. Missing usage is not invented. |
| A44 | Guided STT/TTS provider setup and supported model/voice/language/automatic-speech defaults | Basic schema-supported portion only. Engine installation and advanced tuning are excluded. |
| A45 | Settings search across owning destinations and supported field labels | Import/export/reset remain P2. |

## State and transport

`lib/core/services/administration_repository.dart` holds the captured connection
and creates explicit profile interfaces. Profile writes verify that the canonical
profile still exists, then send the same name in query and JSON body. Server
collection/runtime operations do not acquire the selected-profile query.
Administration-owned RPC transports avoid replacing chat event handlers.

Settings submit sparse patches and verify affected fields. Already-changed fields
are detected before writing; failure, partial readback and uncertain completion
retain the visible draft. This reduces accidental overwrites but does not add an
atomic revision contract to Hermes. Open editors retain their target after profile
selection changes. In-flight saves disable duplicate submission.

Refresh failures retain the previous observation with its last-checked time.
Malformed responses render an unavailable state. OAuth polling and cancellation
keep their returned session/flow identity. Background jobs verify both returned
action name and PID; a same-name replacement cannot become the original job's
success. Authenticated HTTP DELETE preserves the JSON body across an auth retry
and returns the backend result rather than synthesizing success.

## Validation

Focused coverage lives in `test/administration_repository_test.dart`,
`administration_screens_test.dart`, `administration_navigation_test.dart`,
`administration_recovery_test.dart` and `administration_transport_test.dart`, with
`test/support/administration_fixture.dart`. It exercises two-server/two-profile
isolation, root-account targeting, vanished profiles, late selection changes,
stale edits, rejected/partial/uncertain saves, action replacement, credential
session cancellation, MCP readback, display-only rename and unsupported model
controls. Existing shell tests cover retaining the open chat and unsent draft.

Flutter phone renders were generated using real Roboto and Material icon fonts:
390×844 tab roots in both themes, 130% text with no selected profile, and an editor
with a 280dp keyboard inset. Separate editor checks use 360dp width and 130% text;
the existing shell regression checks 200% text. Images are reproducible in
`build/administration-preview/`. They are host-rendered Flutter widgets, not
screenshots of an installed Android build. The keyboard check reserves the OS
inset; it does not render an Android keyboard.

The design task reviewed the rendered roots and ownership/navigation code. Its
four findings were resolved: opening a Server profile selects the Profile tab;
runtime `current` resolves through profile display metadata; runtime Logs stays
reachable when identity is unavailable; diagnostics links open captured access
and MCP editors; and all previews now use the delivered shared Studio theme.
Mint and Iris are rendered in both light and dark themes. The final navigation
tests cover these corrections.

```powershell
.\scripts\invoke-flutter.ps1 -ToolchainRoot 'C:/Users/rober/Development/android-dev' -FlutterArguments @('analyze','--no-pub')
.\scripts\invoke-flutter.ps1 -ToolchainRoot 'C:/Users/rober/Development/android-dev' -FlutterArguments @('test','--no-pub','--concurrency=2')
.\scripts\invoke-flutter.ps1 -ToolchainRoot 'C:/Users/rober/Development/android-dev' -FlutterArguments @('test','--no-pub','test/administration_navigation_test.dart','--dart-define=CAPTURE_ADMINISTRATION=true','--dart-define=CAPTURE_FONT_DIR=C:/Users/rober/Development/android-dev/flutter/bin/cache/artifacts/material_fonts')
```

Final results: static analysis reports no issues. The full host suite passes
**1,555 tests**, with **10 skipped**, in 2m09s, including the final Studio
model-picker correction. The focused administration suite contains 33 tests.
All tab roots, the large-text missing-profile view and the keyboard-inset editor
were rendered and visually inspected using the production theme. `git diff --check`
also passed. No Android deployment or live mutation acceptance is implied.
Logs are local build artifacts: `build/administration-analyze.log` and
`build/administration-host-tests.log`.

## Remaining release and backend acceptance

The follow-up [emulator acceptance record](ADMINISTRATION_EMULATOR_ACCEPTANCE_2026-09-14.md)
supersedes the initial host-only validation limits below. It records actual
Android runs against the installed local Hermes backend, the resulting fixes,
and operations still limited by backend or external-account requirements.

- A08 memory mutation, A24 per-tool MCP mutation, A09 arbitrary-owner pool detail,
  and A28 exact retained-file sizes need the backend contracts described above.
- Generic configuration and skill preflight/readback are not atomic concurrency
  protection; another client can still race between calls.
- New destructive/provider/install/diagnostic flows were verified with injected
  fixtures and inspected source, not executed against the user's active server.
  Prior read-only local-server evidence remains in the scope audit. Disposable
  backend integration and Android browser-return/process-death testing remain
  release acceptance work.
- Pending OAuth/action screens do not persist across Android process death.
  Reopening access and refreshing status is required; no saved pending session is
  silently restarted.
- This implementation was subsequently committed and pushed to main as
  `d32cc83`. The follow-up acceptance run installs a test APK on a disposable
  emulator. Installed backend source is unchanged.
