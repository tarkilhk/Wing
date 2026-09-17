# Administration

Administration uses Profile, Server and Health tabs. The selected server stays visible. Profile opens with a compact profile brief and current-value navigation: Models and reasoning, Identity, Memory and Behavior under Agent setup; Skills and tools, Access and connectors and Scheduled tasks under Capabilities and automation. Server has Connection, Providers, Profiles and Runtime. Health separates runtime observations from selected-profile diagnostics and usage.

Read the [ownership handoff](design/2026-09-14-administration-handoff.md) before changing these flows. The [roadmap](ADMINISTRATION_ROADMAP.md) preserves selected priorities and exclusions.

## Overview and navigation

The header contains the single visible Refresh administration action. It updates
workspace/profile discovery, overview observations and runtime identity. It preserves
the selected tab and diagnostic results, and does not run operational checks.
Pull-to-refresh remains available on the Profile list.

Overview reads are independent observations for a captured profile. A failed read
retains its last confirmed value and freshness; missing configuration stays
unavailable. Entry performs no inference, installations, connector tests or Doctor.
The profile brief groups the shared Chats profile chips with a one-line description
and direct Identity edit, or Describe this agent when absent. Selected profiles are
kept in view. Setup needs, expired sign-ins and schedule issues use separate semantic
attention labels; task names stay on one line with run time/outcome beneath.
Returning from an editor refreshes only the affected observations and briefly emphasizes changed values;
reduced motion suppresses the emphasis. Tabs and search preserve their observations
and scroll context. Search shows the full owner/editor/field path and opens the exact field without
focusing its keyboard.

Skills and tools opens Capabilities first, grouped into Needs setup, Enabled
capabilities and Not enabled. Installed skills is the adjacent view; the selector
stacks at narrow widths or enlarged text. Tool details combine
separate enablement/setup/platform facts with the owning setup route. Skill library,
Discover skills and Agent plugins remain distinct secondary destinations in the
Browse and manage skills menu.
Provider inventories use compact status/source/expiry rows, direct expired-sign-in renewal
and an explicit Add service key catalog. Account details explain the observed source
and link to the canonical shared account. Memory leads with retained entries and a
short read-only disclosure; source metadata is shown only when reported.

Health places selected-profile findings before usage and runtime utilities. Check
coverage and freshness describe access/setup/credential observations; they do not
certify inference. Findings retain their state through owning-editor visits and
search, with explicit recheck. Runtime Health retains Doctor/audit observations and their timestamps while
reviewing results or switching tabs. Reviewing output reads the same operation;
Run again is separate and unavailable until its prior outcome is known. A failed
refresh retains the last output and observation time. Results lead with the outcome
and next step, with raw output disclosed below; completion does not certify health.
Usage compares sortable model totals with formatted calls, input/output tokens and estimated USD costs before expansion.
Cost bars use only known, finite, nonnegative costs and state their coverage; a zero
total draws no shares, and unreported cost remains unavailable.

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
| A16 | Dedicated full-screen description/SOUL editor under Identity | Uses the captured profile gateway; existing readback behavior is retained. |
| A17 | Create, clone configuration, rename and delete under Server / Profiles | Default profile has presentation-only rename and no delete action. Creation/rename/deletion is followed by discovery. Unconfirmed outcomes remain unconfirmed. Full-data/channel cloning and optional multi-step setup are not offered. |
| A18–A19 | Recorded skill usage ordering, provenance, complete instructions, edit/archive agent-owned skills | Bundled instructions are read-only. Existing changed content is detected before saving; this is not a server compare-and-swap guarantee. |
| A20 | Official Hub/search, provenance preview, install, uninstall and group update | Tracks returned background action identity and actual exit status. Install/update acceptance requires an authorized target and actual action result. |
| A22 | Scoped toolset providers, effective key readiness, model selection, explicit post-setup action | Setup explains host requirements and tracks the returned action. An effective inherited key is not offered as removable from the profile. |
| A24–A25 | MCP inventory/enablement, cached status, explicit Test, returned tool details and prompt/resource counts, browser OAuth, remove; global reload under Server / Runtime | Per-tool edits remain unavailable because the backend replaces the whole map. Missing cached status is not disconnected. OAuth uses the configured server callback. Runtime reload is process-wide. |
| A27 | Agent-plugin inventory/status and individual enablement | Selected P1 portion only. Install/remove/update and Desktop UI extensions are outside this slice. |
| A28 | Memory enablement and character budgets | Exact retained-file sizes lack an arbitrary-profile contract and are explicitly unavailable. |
| A31 | Compression percentages, capacity illustration, enablement and protected recent messages | Schema-supported basic controls only; advanced context-engine work remains P2. |
| A32 | Approval mode/timeout, command allowlist, reload confirmation | Backend policy is distinct from per-chat controls. |
| A33 | Secret redaction, private-URL access and checkpoint enablement | Uses `security.allow_private_urls`; browser-profile grants and advanced recovery remain P2. |
| A36–A37 | Existing connection management and authenticated profile diagnostics | Device connection settings and backend policy remain separate. |
| A38–A39 | Bounded log categories/severity/search; explicit Doctor and security audit with action status | Runtime scope is independent of mobile selection. No automatic repair or new restart action. |
| A41 | Existing backend version and eligible-update flow under Runtime | Request acceptance does not prove a completed update. |
| A42 | Rolling 1/7/30/90/365-day usage with per-model sessions, calls, tokens and estimated cost | Hermes estimates, not provider invoices. Missing usage is not invented. |
| A44 | Guided STT/TTS provider setup and supported model/voice/language/automatic-speech defaults | Basic schema-supported portion only. Engine installation and advanced tuning are excluded. |
| A45 | Searchable owner paths and task vocabulary with exact-field scrolling, emphasis and explicit clearing | Import/export/reset remain P2. |
| A48–A49 | Profile-owned scheduled tasks: search/filter, details, create/edit, templates, model/delivery choices, pause/resume/run/delete and recent run conversations | Hermes executes schedules. One-time completion may remove the task. Script-only tasks may have no conversation. No Android scheduler or new notification subscription is created. |

## Scheduled tasks

Open Profile / Scheduled tasks to manage the selected profile's routines. Each
task shows its next run and state. The overview chooses the earliest eligible
server timestamp separately from running/attention ordering. Its latest-run summary
covers only tasks still listed; an ended conversation does not establish success. Tap it for instructions, delivery, model,
last-run details and recent conversations. Search and All / Active / Paused /
Needs attention filters affect only this list. Opening a run works independently
of the Chats “Include automated chats” filter.

New task supports daily, weekday, weekly, monthly, hourly and interval schedules,
one-time dates/delays, and custom expressions. Server templates provide starting
points. Recurrences use Hermes' effective timezone; Wing labels it as Hermes time
when the server does not establish its name. Run timestamps use phone time.
One-time dates chosen on the phone are sent as explicit UTC instants. Editing a
name or instructions leaves an unchanged schedule's anchor intact.

“Save on server” stores results in Hermes, not on the phone. Other choices come
from the connected server's delivery catalog, which is not a claim that every
profile has its own configured channel. Destinations missing a home channel
need server setup. Missing catalog entries are not silently removed from an
existing task. A model override is paired with its provider; Profile default
resolves at run time. Custom endpoint routing and script/skill execution settings
remain server-managed; common-field edits do not erase them.

Run now can take as long as the task itself. Leaving its detail screen does not
resubmit or cancel it. Running a paused task explicitly confirms “Resume and
run”; pausing a schedule does not stop a run already underway. A lost response
keeps an uncertainty notice and blocks another request until reconciliation or
explicit review. Only task IDs, operation names and prior run timestamps are
journaled locally, not instructions. Partial scheduler registration failures
retain the saved task identity and prevent duplicate creation.

Recent runs starts with 20 conversations and can expand to the latest 100.
Failures remain distinct from an empty history. No task-specific Stop command,
script upload, workflow builder or unlimited history is provided.

## Ownership and credentials

Shared provider accounts explicitly target the discovered canonical `default` root. An omitted or `current` profile can mean the dashboard's launch home, so it is not a substitute for verified root ownership.

Profiles inherit root provider state when they have no local state. A nonempty local credential pool shadows that provider's root pool. Removing a profile override can expose shared access again; it must not promise to disconnect the provider everywhere. External CLI credentials have separate ownership, and not every Hermes Codex account is externally managed.

Capture the connection and canonical profile when an editor opens. Profile writes recheck that identity and use it consistently in query and body. Server collection/runtime operations do not inherit the currently selected profile. Administration RPC transports must not replace chat event handlers.

Model defaults apply to new sessions. Per-chat models use a separate session API. Provider resolution or a pool row does not prove a working login or inference. A Nous selection requiring `needs_nous_auth` is saved but not active yet; follow the returned `is_active` state for provider flows. Service-only setup entries such as X, Home Assistant, Spotify and Langfuse must not offer a meaningless Use provider action.

## Saving and recovery

Settings and Identity show their captured target and an unsaved-change count, with
reachable Close/Save actions above the keyboard. Compression inputs display exact
decimal percentages and serialize fractions; the diagram shows configured capacity,
not live usage. Detected settings conflicts compare Current server value with Your
value. Keep my value or Use server value resolves each field, followed by a fresh
comparison before any write. Failed/partial saves bring their explanation into view.

Submit sparse settings patches and read back the affected fields. Keep the form after a rejection, partial result or uncertain completion; guard duplicate submission. A preflight comparison can detect an already changed value but cannot make separate calls atomic against another client.

Refresh failure retains the previous observation with its last-checked time. Malformed or missing data is unavailable, not an invented empty value. OAuth keeps its returned flow identity through polling/cancellation. Pending OAuth and background-action screens do not survive Android process death; reopen the owning page and refresh instead of silently starting another flow.

Track background actions by returned name and PID. A same-name replacement is not the original action's success. Authenticated DELETE retries must preserve the request body and report the backend's real outcome.

Usage supports rolling 1, 7, 30, 90 and 365-day ranges. Sessions, calls, tokens and USD costs are server-reported estimates, not provider invoices. Missing costs stay unknown. Do not add auxiliary breakdowns to totals that already include them.

## Backend limits and verification

Memory edit/delete needs stable IDs and safe concurrent writes. Per-tool MCP mutation needs a contract that does not replace an unchecked whole map. Arbitrary-owner credential-pool detail and exact retained-file sizes are unavailable. These restrictions do not block independent browsing, enablement or supported settings.

Recorded native acceptance against Hermes 0.21.2 includes real profile lifecycle, settings readback, temporary credential-source changes and MCP operations using disposable data. Provider account approval, real inference for every route, SDK installation and backend self-update are not established by that run. See [Testing](TESTING.md) and [upstream bugs](UPSTREAM_HERMES_BUGS.md), including the Windows MCP profile-deletion failure.
