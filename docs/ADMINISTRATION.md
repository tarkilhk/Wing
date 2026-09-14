# Administration

Administration uses Profile, Server and Health tabs. The selected server stays visible. Profile has Defaults, Identity, Memory, Skills and tools, Access and connectors, and Behavior. Server has Connection, Providers, Profiles and Runtime. Health separates runtime observations from selected-profile diagnostics and usage.

Read the [ownership handoff](design/2026-09-14-administration-handoff.md) before changing these flows. The [roadmap](ADMINISTRATION_ROADMAP.md) preserves selected priorities and exclusions.

## Current controls

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
| A20 | Official Hub/search, provenance preview, install, uninstall and group update | Tracks returned background action identity and actual exit status. Install/update acceptance requires an authorized target and actual action result. |
| A22 | Scoped toolset providers, effective key readiness, model selection, explicit post-setup action | Setup explains host requirements and tracks the returned action. An effective inherited key is not offered as removable from the profile. |
| A24–A25 | MCP inventory/enablement, cached status, explicit Test, returned tool details and prompt/resource counts, browser OAuth, remove; global reload under Server / Runtime | Per-tool edits remain unavailable because the backend replaces the whole map. Missing cached status is not disconnected. OAuth uses the configured server callback. Runtime reload is process-wide. |
| A27 | Agent-plugin inventory/status and individual enablement | Selected P1 portion only. Install/remove/update and Desktop UI extensions are outside this slice. |
| A28 | Memory enablement and character budgets | Exact retained-file sizes lack an arbitrary-profile contract and are explicitly unavailable. |
| A31 | Basic compression enablement, threshold, target and protected recent messages | Schema-supported basic controls only; advanced context-engine work remains P2. |
| A32 | Approval mode/timeout, command allowlist, reload confirmation | Backend policy is distinct from per-chat controls. |
| A33 | Secret redaction, private-URL access and checkpoint enablement | Uses `security.allow_private_urls`; browser-profile grants and advanced recovery remain P2. |
| A36–A37 | Existing connection management and authenticated profile diagnostics | Device connection settings and backend policy remain separate. |
| A38–A39 | Bounded log categories/severity/search; explicit Doctor and security audit with action status | Runtime scope is independent of mobile selection. No automatic repair or new restart action. |
| A41 | Existing backend version and eligible-update flow under Runtime | Request acceptance does not prove a completed update. |
| A42 | Rolling 1/7/30/90/365-day usage with per-model sessions, calls, tokens and estimated cost | Hermes estimates, not provider invoices. Missing usage is not invented. |
| A44 | Guided STT/TTS provider setup and supported model/voice/language/automatic-speech defaults | Basic schema-supported portion only. Engine installation and advanced tuning are excluded. |
| A45 | Settings search across owning destinations and supported field labels | Import/export/reset remain P2. |

## Ownership and credentials

Shared provider accounts explicitly target the discovered canonical `default` root. An omitted or `current` profile can mean the dashboard's launch home, so it is not a substitute for verified root ownership.

Profiles inherit root provider state when they have no local state. A nonempty local credential pool shadows that provider's root pool. Removing a profile override can expose shared access again; it must not promise to disconnect the provider everywhere. External CLI credentials have separate ownership, and not every Hermes Codex account is externally managed.

Capture the connection and canonical profile when an editor opens. Profile writes recheck that identity and use it consistently in query and body. Server collection/runtime operations do not inherit the currently selected profile. Administration RPC transports must not replace chat event handlers.

Model defaults apply to new sessions. Per-chat models use a separate session API. Provider resolution or a pool row does not prove a working login or inference. A Nous selection requiring `needs_nous_auth` is saved but not active yet; follow the returned `is_active` state for provider flows. Service-only setup entries such as X, Home Assistant, Spotify and Langfuse must not offer a meaningless Use provider action.

## Saving and recovery

Submit sparse settings patches and read back the affected fields. Keep the form after a rejection, partial result or uncertain completion; guard duplicate submission. A preflight comparison can detect an already changed value but cannot make separate calls atomic against another client.

Refresh failure retains the previous observation with its last-checked time. Malformed or missing data is unavailable, not an invented empty value. OAuth keeps its returned flow identity through polling/cancellation. Pending OAuth and background-action screens do not survive Android process death; reopen the owning page and refresh instead of silently starting another flow.

Track background actions by returned name and PID. A same-name replacement is not the original action's success. Authenticated DELETE retries must preserve the request body and report the backend's real outcome.

Usage supports rolling 1, 7, 30, 90 and 365-day ranges. Sessions, calls, tokens and USD costs are server-reported estimates, not provider invoices. Missing costs stay unknown. Do not add auxiliary breakdowns to totals that already include them.

## Backend limits and verification

Memory edit/delete needs stable IDs and safe concurrent writes. Per-tool MCP mutation needs a contract that does not replace an unchecked whole map. Arbitrary-owner credential-pool detail and exact retained-file sizes are unavailable. These restrictions do not block independent browsing, enablement or supported settings.

Recorded native acceptance against Hermes 0.21.2 includes real profile lifecycle, settings readback, temporary credential-source changes and MCP operations using disposable data. Provider account approval, real inference for every route, SDK installation and backend self-update are not established by that run. See [Testing](TESTING.md) and [upstream bugs](UPSTREAM_HERMES_BUGS.md), including the Windows MCP profile-deletion failure.
