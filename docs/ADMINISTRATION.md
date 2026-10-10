# Administration

Wing puts everyday profile settings, server checks and usage in three clear places:

| Go to | Use it for |
| --- | --- |
| **Hermes administration** | Models, identity, skills, provider access, MCP connectors and scheduled tasks for the selected profile. |
| **Hermes health** | Host resources, server diagnostics and checks for the selected profile. |
| **Hermes analytics** | Activity, token usage and estimated costs. |

Open these destinations from Wing's navigation drawer. Bots also opens the existing editors through **Bot settings**, retaining that row's connection and profile even when it differs from the selected chat. Its appearance, duplicate and profile-management actions are described in the [Bots guide](BOTS.md). The connection name and status open connection details; the server version opens Versions & updates. The rest of this guide records the exact controls and server boundaries for contributors.

Read the [ownership handoff](design/2026-09-14-administration-handoff.md) before changing these flows.

Target correction, 17 September 2026: Wing follows the latest upstream Hermes as
specified in [AGENTS.md](../AGENTS.md). Provider credentials belong to profiles;
upstream removed automatic root `auth.json` inheritance. The Providers entry has
been removed from the Server tab and administration search routes provider queries
to Profile. Provider recovery now keeps this scope and removes the obsolete
shared-account links and root-inheritance wording.

## Overview and navigation

The header contains the single visible Refresh administration action. It updates
workspace/profile discovery, overview observations, scoped provider configuration
and scoped readiness. It preserves diagnostic results and does not run operational checks.
Pull-to-refresh remains available on the Profile list.

Overview reads are independent observations for a captured profile. A failed read
retains its last confirmed value and freshness; missing configuration stays
unavailable. Entry performs no inference, installations, connector tests or Doctor.
The profile brief groups the shared Chats profile chips with a one-line description
and direct Identity edit, or Describe this agent when absent. Selected profiles are
kept in view. Setup needs, expired sign-ins and schedule issues use separate semantic
attention labels; task names stay on one line with run time/outcome beneath.
Long-press an Administration profile pill to choose one of Desktop's twelve profile
hues or Automatic color. The choice is saved on this device for that connection and
also colors the profile square in Chats. Automatic uses Desktop's name-derived hue;
the default profile is neutral. Color edits do not switch profiles or call Hermes.
The picker follows Studio light/dark tokens and remains reachable at 320 dp with
200% text. Verified with `profile_selector_test.dart`, `chat_profile_bar_test.dart`
and `administration_navigation_test.dart`, plus rendered Administration captures
in both themes at normal and enlarged text. Desktop reference: [profile color
picker](https://github.com/NousResearch/hermes-agent/blob/main/apps/desktop/src/app/chat/sidebar/profile-switcher.tsx)
and [local color storage](https://github.com/NousResearch/hermes-agent/blob/main/apps/desktop/src/store/profile.ts).
Returning from an editor refreshes only the affected observations and briefly emphasizes changed values;
reduced motion suppresses the emphasis. Health visits and search preserve profile
observations and scroll context. Search shows the full owner/editor/field path and opens the exact field without
focusing its keyboard.

Skills and tools opens Capabilities first, grouped into Needs setup, Enabled
capabilities and Not enabled. Installed skills is the adjacent view; the selector
stacks at narrow widths or enlarged text. Tool details combine
separate enablement/setup/platform facts with the owning setup route. Skill library,
Discover skills and Agent plugins remain distinct secondary destinations in the
Browse and manage skills menu. Each installed skill has an eye action beside its
enablement switch to open instructions directly; expanding the row shows its
description.
Installed skill details reuse the same `SkillDocumentViewer` and received-document
selection as Activity skill reads. The name's copy button copies only the name;
raw/formatted, share and content-copy controls belong to the instructions card.
The bottom reader dock opens Contents or steps between sections. Hold or drag
the six-dot grip to browse numbered sections, then release to jump.
Quiet metadata shows supplied version, author, directory category and tags.
API-discovered reference files precede Activity and open the same reader.
Activity summarizes recorded uses and patches/edits across observed profiles;
its centered disclosure shows separate profile charts, secondary 90-day read
requests and valid last-change dates. Missing records remain unknown and missing
sections are omitted. The administration session retains profile scope,
refresh/recovery and eligible edit, archive or uninstall actions in the
icon-only skill-actions menu. Viewing does not issue edits. A content-only
receipt does not invent a source path or file-sharing capability.

Integration inspected unmodified upstream Hermes commit
[`1744a19e0df568c647e4f3ff9c37f2a284a282fb`](https://github.com/NousResearch/hermes-agent/tree/1744a19e0df568c647e4f3ff9c37f2a284a282fb)
on 9 October 2026: stock skills catalog/content, profile discovery, filesystem
listing/text APIs and analytics usage. Wing reads returned `.usage.json` content
through the filesystem API for exact counters; it uses no SSH or custom backend
endpoints. Analytics read requests remain distinct from use/change counters.
Provider inventories use compact status/source/expiry rows and an explicit Add
service key catalog. Account details offer renewal, sign-in, status checks and
removal according to the observed credential source. Memory leads with retained entries and a
short read-only disclosure; source metadata is shown only when reported.

## Health observations

The owner-approved clear-result wording uses `Access is set up`, enabled tool-group
counts with setup gaps, passed/failed/unavailable connector counts, and scheduled
task counts with recorded errors. Empty inventories say so explicitly. The
What’s checked? dialog explains that configuration checks do not execute tools,
connector checks do not exercise their actions, and task checks do not run jobs.
Reverified stock Hermes at
[`1af1db281e7274581cb61fdd03c64f822fbebb83`](https://github.com/NousResearch/hermes-agent/commit/1af1db281e7274581cb61fdd03c64f822fbebb83):
`tui_gateway/methods_config.py`, `hermes_cli/web_routers/tools.py`,
`hermes_cli/tools_config.py`, and `hermes_cli/web_routers/mcp.py`. No new API calls.

Server and Profile each display one check time in the heading. The profile time
is the end of its most recent refresh attempt, qualified as incomplete if any of
the four visible checks lacks a result; reported problems still count as completed
checks. The Server completion time advances only when both diagnostics in a
section refresh finish. Individual reruns retain that shared time. If diagnostics
were first run separately, their oldest result establishes initial section coverage.
Diagnostic generation IDs keep retained output from satisfying a newer refresh,
including after restarting the app. Detailed result pages retain their own times.
The health-result cache uses the v2 schema for these section records and count-based
summaries; older cached Health snapshots are not restored. Other app data is unchanged.

Health has three groups in order: Host, Server, Profile. Host is described below.
Server owns Doctor, security audit and Logs. Its refresh icon
starts Doctor and security audit together, without opening their details or a
confirmation dialog. It is disabled while either diagnostic is starting, running
or has an uncertain completion. Each operation retains its own result; a failed
start does not prevent the other operation from running. The icon shows a spinner
while diagnostics start or run, matching Profile refresh.
Doctor and security audit details rerun from their top-bar play action, with no
bottom rerun button; result polling remains automatic. There is no runtime-profile
label. Diagnostic confirmations and results identify the server. Profile uses
selection from the shared header,
a refresh icon beside its heading, four stable rows (Model access, Tool setup, Connectors,
Scheduled tasks). There is no global health verdict. Server diagnostics run on first entry and retain their separate progress and results.

In diagnostic details, an unfinished or uncertain run shows its status-read time
as “Last updated”; “Checked” appears only after confirmed completion. Doctor’s
complete findings report is a completed check requiring attention; its stock
exit code 1 does not by itself mean the diagnostic failed.

Health owns its profile observations, so opening Administration first is unnecessary.
Opening Health or selecting a profile reuses that profile’s saved results for 24 hours.
A profile with no saved refresh, or one at least 24 hours old, automatically checks all four rows:
model credential resolution, enabled-tool configuration, enabled connector connection
probes, and scheduled-task errors or uncertain actions. The Profile refresh icon and
pull-to-refresh repeat the same checks. Returning from provider recovery also checks
again. Pending refreshes are shared per profile; another profile can refresh immediately,
and late results remain attached to their captured scope. No model prompt is sent.
Model access is a passive row directly in Health. It shows credential status,
and model/provider. There is no model/provider detail destination,
Change model control, routine account-management shortcut, or row navigation.
The Profile refresh icon repeats the checks. A reported provider failure
reveals Fix access, which opens the profile's existing account editor; an
unconfirmed alternate route offers Review access. An incomplete check offers Retry,
and server authentication rejection offers Review connection. Healthy and unchecked
states have no recovery actions. What’s checked? explains the checks and their limits.
The headings own section times; these describe check completion, not a healthy verdict.

The row uses the retained credential result. Configuration presence and unknown
provider catalog entries do not substitute for it. Successful checks require the
canonical profile and resolved model/provider. A different resolved model/provider
is named explicitly and does not validate the selected route; aliases are not guessed
to be fallbacks. Unchanged selections retain results; an observed model/provider
change or return from the recovery editor clears them, including in-flight results.
Model selection and routine account management remain in Administration. Recovery
editors capture the profile they save to.

The credential check calls only `setup.runtime_check`, scoped to the captured
canonical profile. Verified against latest stock upstream
[`783f854b0fb2bb224cedf972b40adfc77e9c818f`](https://github.com/NousResearch/hermes-agent/blob/783f854b0fb2bb224cedf972b40adfc77e9c818f/tui_gateway/methods_config.py#L296)
on 19 September 2026: without a provider override it resolves the startup model and
configured fallback chain. This establishes credential resolution, not successful
inference or available quota. Resolution may use the provider's credential renewal;
opening Health runs this credential check when the saved profile refresh is absent or expired. Only known missing-credential
messages are described as missing credentials. Other negative results say Provider
check failed; arbitrary server exception text is not displayed. A missing/mismatched
success scope or malformed response is incomplete, never success. Transport failures
are inconclusive, never evidence that credentials are missing.
The selected model/provider comes from stock [`GET /api/model/info`](https://github.com/NousResearch/hermes-agent/blob/f971bbf51298e846834d3d76e18d763223bd58ec/hermes_cli/web_routers/models.py#L40),
refreshed before each credential check and after editing. No backend changes are needed.

Connector checks use stock [`POST /api/mcp/servers/{name}/test`](https://github.com/NousResearch/hermes-agent/blob/783f854b0fb2bb224cedf972b40adfc77e9c818f/hermes_cli/web_routers/mcp.py#L166)
with the captured canonical `profile`, verified at the same upstream commit. Hermes
connects, lists capabilities, then disconnects; a local connector may start its configured
process. Disabled connectors are skipped. Empty profiles say No connectors configured.
Failed probes and unavailable/malformed responses remain distinct from successful checks.
Checks do not save settings or reload running chats. Tools reports enabled toolsets with
missing setup; tasks reports recorded errors and uncertain actions, without executing tools
or scheduled jobs.

Configuration does not become unknown just because five minutes pass. Failed
refreshes retain the previous result and timestamp with a local qualification;
actual provider credential expiration still becomes a reported failure. Connector
configuration never establishes connectivity. Switching profiles detaches old
observations immediately, and late responses cannot replace the current profile.

Health state belongs to the connection, not its route. Navigating away keeps
in-flight checks alive. Server diagnostic results and a separate result/refresh
time for every canonical profile are saved on the device and restored after app
restart. Storage is scoped by connection ID and endpoint/authentication identity.
Profile snapshots contain health metadata rather than connector commands,
environment values or provider secrets. Completed diagnostic details use their
saved output without issuing another status request. An unfinished restored run
resumes status reads for its saved action identity without launching a new process.
If a valid server status no longer identifies that run, its unfinished outcome
becomes unavailable and the Server spinner stops. The saved output remains
reviewable; use the diagnostic's play action or Run all diagnostics to start fresh.
Health does not automatically restart a lost unfinished run. Connection failures
keep tracking the same run and do not enable a duplicate start.

On Health entry, each completed server diagnostic at least 24 hours old runs
again automatically; diagnostics with no prior attempt trigger their initial run.
An unconfirmed start is saved too: reopening Health never repeats it automatically.
The row keeps an explicit Run action for the user to retry.
Profile and server clocks are independent. Manual refresh remains available,
and an in-flight refresh is shared across repeated visits. Old observations remain
available while replacement checks are pending. Provider credential expiry is
still evaluated from the saved expiry timestamp.

Connectivity recovery retries temporary reads up to three attempts with one- and
two-second delays. Known diagnostic runs keep polling after an extended outage.
Starts retry only failures known to precede delivery, including transient
pre-dispatch authentication failures and Android/Linux connect/DNS failures.
A lost POST response, timeout after dispatch, server error or reset is not replayed:
stock Hermes cannot associate an idempotency key with a diagnostic start.
Authentication preparation has its own deadline, so a timed-out preparation
cannot later dispatch the abandoned diagnostic.

Retry contract verified on 19 September 2026 against upstream main
[`a11bac476bb2a2129fdffca9511d41260fa5f51f`](https://github.com/NousResearch/hermes-agent/commit/a11bac476bb2a2129fdffca9511d41260fa5f51f):
[`ops.py`](https://github.com/NousResearch/hermes-agent/blob/a11bac476bb2a2129fdffca9511d41260fa5f51f/hermes_cli/web_routers/ops.py)
uses separate Doctor and security-audit POST routes;
[`_common.py`](https://github.com/NousResearch/hermes-agent/blob/a11bac476bb2a2129fdffca9511d41260fa5f51f/hermes_cli/web_routers/_common.py)
returns the spawned name/PID, and
[`web_server_gateway.py`](https://github.com/NousResearch/hermes-agent/blob/a11bac476bb2a2129fdffca9511d41260fa5f51f/hermes_cli/web_server_gateway.py)
launches a new process on every call and overwrites the same-name action handle.
All recovery and persistence changes are client-only.

Server diagnostic results retain their action identity, captured scope, output and
timestamps through detail navigation and profile switches. Run starts the diagnostic
without opening its result screen; tapping the row opens details. Health polls
running diagnostics every three seconds and updates Doctor issue counts in place.
Reviewing output reads
the same operation. Run again is a separate detail action, offered only for a known
finished operation. Doctor summaries show parsed findings; full output remains
available. Other operations show their actual output. Exit zero alone never means
no issues. Security audit shows its vulnerability count in Health, then the full
finding/component total and expandable severity groups in details. Each finding
retains its package, source component, advisory, description and reported fixed
versions. Audit notices remain separate from vulnerability counts. Diagnostic
output is available in a disclosure, collapsed by default. Only a complete current
report with exit 0 or 1 supplies structured audit counts; exit 2 is an audit error.
Unrecognized or truncated output never implies no vulnerabilities.
Stock Hermes exposes no remote Doctor repair action, so Wing adds none.
Each Doctor finding has an **Ask Hermes** action that opens a new chat using the
selected profile, with that finding and the available diagnostic log in an
editable, unsent draft. The prompt asks for an explanation and proposed solution,
including data-loss risks and verification, and says not to make changes or run
repairs yet. The user reviews and sends it. Doctor output is requested up to the
stock limit of 2,000 lines / 256 KiB; it is not guaranteed to be complete.

Run-all contract rechecked on 19 September 2026 against upstream
[`96b6c534c3fc1681ecbf2df0f92d1b3c6cce4f62`](https://github.com/NousResearch/hermes-agent/commit/96b6c534c3fc1681ecbf2df0f92d1b3c6cce4f62):
`hermes_cli/web_routers/ops.py` still exposes separate POST endpoints for Doctor
and security audit, with no profile argument. Both use `_spawn_action`, which
calls `spawn_profile_action(None, ...)` in the dashboard's environment. Wing does
not select a diagnostic profile or claim that profile discovery establishes one.
Run all composes these existing endpoints entirely in the client.
Verified on 18 September 2026 against stock upstream
[`8a492617e1239ab90bd3e3f7794b1e443f37a287`](https://github.com/NousResearch/hermes-agent/commit/8a492617e1239ab90bd3e3f7794b1e443f37a287):
- `hermes_cli/web_routers/ops.py`: Doctor and security audit take no profile or repair flag.
- `hermes_cli/web_routers/status.py`: Logs supports file, level and search; returns `lines`, with no profile parameter.
- `hermes_cli/web_routers/analytics.py`: model usage accepts an explicit profile and day range.
- `tui_gateway/methods_config.py`: `setup.status` observes configuration; `setup.runtime_check` resolves the selected profile's runtime credentials without model inference.

Usage uses compact period buttons, a daily token grid, animated composition bars
and a stacked token trend. Tappable chart titles switch model/token grouping;
Tokens/Cost controls are independent for each chart. Breakdown rows combine all
providers and auxiliary contributions for each model and have no detail action.
The header dropdown offers profiles only; chart toggle icons precede their titles. Unknown costs stay unavailable
and partial coverage is stated.
Logs keeps server source, severity, submitted text search, a 100-line limit and
explicit empty/error states.

## Host resources

Open Hermes health to see Host, then Server, then Profile. Host displays the
connected machine's identity, compact CPU/memory/disk meters, boot uptime and
load averages. CPU count and Python version appear only in machine details.
Tap the machine row for available memory, free disk space and API-process
details. The Host refresh icon reads resources only; it has one
spinner, with no extra loading bar. The Server icon still runs diagnostics.

Verified on 7 October 2026 against stock upstream
[`05eecbcd972c8737ebc7722ea08aab47fb538043`](https://github.com/NousResearch/hermes-agent/commit/05eecbcd972c8737ebc7722ea08aab47fb538043):
`hermes_cli/web_routers/status.py`, `gateway/memory_status.py` and
`gateway/disk_status.py`. `GET /api/system/stats` supplies host identity and
optional CPU usage, memory/disk bytes and percentages, load, boot uptime and
API-process data. Disk describes the Hermes data volume; process memory is not
the sum of all agents or gateways. A missing or malformed optional probe stays
unavailable. `GET /api/status` independently supplies advisory pressure, which
does not establish service availability. Memory pressure has its own heartbeat
sample time and becomes unknown after 150 seconds; disk pressure is sampled live.
No backend changes or older-server endpoint alternatives are required.

`ProfileWorkspaceController.hostResources()` returns one connection-owned
`HostResourcesSession`, shared by Health and other consumers. Its immutable
`HostResourcesState` exposes separate `HostReading<HostSystemStats>` and
`HostReading<HostPressureStatus>` values, receipt times and read errors. Failed
refreshes retain the prior value and time, while `isCurrent` rejects error,
stale and future-dated readings. The two endpoints complete independently;
pressure failure does not suppress newly read usage metrics. Concurrent refreshes
coalesce into one pair of reads. No resource data is persisted into the existing
24-hour diagnostic cache.

`watch(interval: ..., active: ...)` expresses each consumer's demand. Health
uses 15 seconds and pauses its watch off-screen and outside the foreground.
All active watches share the shortest requested cadence; closing or pausing one
does not stop another. With no active watches there is no poll. Refresh on
activation reuses any already pending read. Owners and in-flight reads retain
the captured connection adapter; retirement prevents late publication and new
dispatch. Consumers close their watches and remove their listeners. The workspace
retires the host owner before its shared administration adapter.

Alerts reuse this observation through pure `HostThresholdPolicy`, without
UI imports, extra endpoint reads or embedded notification behavior. Callers choose
thresholds and the maximum age (30 seconds by default), then evaluate the stats
reading with an explicit clock. For example:

```dart
final policy = HostThresholdPolicy([
  HostThreshold(HostMetric.cpuPercent, 80),
  HostThreshold(HostMetric.memoryUsedPercent, 85),
  HostThreshold(HostMetric.diskUsedPercent, 90),
  HostThreshold(HostMetric.loadOneMinutePerCpu, 1),
]);
final results = policy.evaluate(resources.state.stats, now: DateTime.now());
```

These example limits are not app defaults. Percent metrics use 0–100; load
uses the selected 1/5/15-minute average divided by logical CPU count, where 1
means one runnable unit per CPU. Each result is above, within or unknown.
Only a value strictly above the limit is above; equality stays within. Missing
CPU count makes normalized load unknown. Missing, expired, failed or future
readings cannot clear an alert as healthy. Alert delivery, persistence and
incident deduplication remain the consuming workflow's responsibility; this
host-data feature does not itself deliver notifications or save alert settings; the alert workflow below owns those decisions.

`test/host_resources_session_test.dart` covers shared demand, independent endpoint
outcomes, immutability, captured identity and retirement. `test/host_thresholds_test.dart`
covers units, limits, freshness and unknown coverage. `test/host_health_view_test.dart`
checks the compact view, independent resource refresh, a single loading indicator,
visibility/background behavior, details and phone layouts in both themes at
normal and 200% text. Render with `CAPTURE_HOST_HEALTH=true` and `CAPTURE_FONT_DIR`
pointing to the Flutter SDK's `bin/cache/artifacts/material_fonts`; captures live
in ignored `build/host-health/`.

## Current controls

| Roadmap | Implemented surface | Boundary |
| --- | --- | --- |
| A01–A02 | Existing main-model editor; capability-gated reasoning and speed defaults | Defaults apply to new sessions. Model identity is rechecked before reasoning/speed saves. Unsupported flags do not create controls. |
| A03–A06 | Existing individual skill/tool toggles and inventories, reached from Skills and tools | Configured, enabled and platform remain distinct. Toolset enablement can start backend setup; it is not proof of readiness. |
| A07 | Searchable retained-memory list and complete detail | Read-only; generated positional identity is used only for reads. |
| A08 | Explicit unavailable state | Edit/delete requires a stable identity and concurrency-safe backend contract. No memory mutation is sent. |
| A09–A11 | Profile access inventories, source labels, stored-key management, supported device-code sign-in, cancellation, disconnect | External CLI login remains external. Pool-account detail cannot be safely attributed to an arbitrary selected owner; it is explicitly unavailable. No credential values are fetched for display. |
| A13 | Auxiliary assignments, automatic choice, reset-all, unavailable-model warning, expensive-model confirmation | Reset-all discloses endpoint-credential clearing. Readback must match the affected tasks. |
| A14 | Ordered fallback list with add/remove/reorder, schema-supported agent/subagent execution controls | Fallback edits check for an already-changed list and verify the saved result. Matches desktop normalization: string entries become provider/model rows, incomplete rows remain editable locally, and only complete pairs are saved after an explicit edit. Opening does not write settings; routing metadata is preserved. Non-list values produce an empty editor. Verified against upstream `21642218445e213b02ea7158f71214022645c9c6` (`apps/desktop/src/app/settings/fallback-models-field.tsx`) on 2026-09-19. Custom provider definitions remain P2. |
| A16 | Dedicated full-screen description/SOUL editor under Identity | Uses the captured profile gateway; existing readback behavior is retained. |
| A17 | Create, clone configuration, rename and delete through the trailing Manage profiles pill in the Profile selector; captured profile editors and Duplicate bot in Bots | Default profile has presentation-only rename and no delete action. Creation/rename/deletion is followed by discovery. Unconfirmed outcomes remain unconfirmed. Profile-manager cloning copies configuration; Bots duplication requests the stock full profile clone with channel bindings excluded. Optional multi-step setup is not offered. |
| A18–A19 | Recorded skill usage ordering, provenance, complete instructions, edit/archive agent-owned skills | Bundled instructions are read-only. Existing changed content is detected before saving; this is not a server compare-and-swap guarantee. |
| A20 | Official Hub/search, provenance preview, install, uninstall and group update | Tracks returned background action identity and actual exit status. Install/update acceptance requires an authorized target and actual action result. |
| A22 | Scoped toolset providers, effective key readiness, model selection, explicit post-setup action | Setup explains host requirements and tracks the returned action. An effective inherited key is not offered as removable from the profile. |
| A24–A25 | MCP inventory/enablement, cached status, explicit Test, returned tool details and prompt/resource counts, browser OAuth, remove; Reconnect MCP tools under MCP connectors (all server profiles) | Per-tool edits remain unavailable because the backend replaces the whole map. Missing cached status is not disconnected. OAuth uses the configured server callback. Runtime reload is process-wide. |
| A27 | Agent-plugin inventory/status and individual enablement | Selected P1 portion only. Install/remove/update and Desktop UI extensions are outside this slice. |
| A28 | Memory enablement and character budgets | Exact retained-file sizes lack an arbitrary-profile contract and are explicitly unavailable. |
| A31 | Compression percentages, capacity illustration, enablement and protected recent messages | Schema-supported basic controls only; advanced context-engine work remains P2. |
| A32 | Approval mode/timeout, command allowlist, reload confirmation | Backend policy is distinct from per-chat controls. |
| A33 | Secret redaction, private-URL access and checkpoint enablement | Uses `security.allow_private_urls`; browser-profile grants and advanced recovery remain P2. |
| A36–A37 | Existing connection management and authenticated profile diagnostics | Device connection settings and backend policy remain separate. |
| A38–A39 | Bounded log categories/severity/search; explicit Doctor and security audit with action status | Runtime scope is independent of mobile selection. No automatic repair or new restart action. |
| A41 | Backend version and update flow under Versions & updates; automatic server checks and a circular-arrows indicator in the global menu | Request acceptance does not prove a completed update. |
| A42 | Rolling 1/7/30/90/365-day usage with per-model tokens and estimated cost | OpenAI Codex subscriptions show a client-calculated API equivalent; other routes use Hermes estimates. Missing usage is not invented. |
| A44 | Guided STT setup, combined speech synthesis provider/voice selection with Play/Stop, and supported model/language/automatic-speech defaults | Vanilla APIs only. Edge uses suggested voices; ElevenLabs loads the account list. Custom voice IDs live under Advanced. Engine installation and advanced tuning are excluded. See [profile voice](PROFILE_VOICE.md). |
| A45 | Searchable owner paths and task vocabulary with exact-field scrolling, emphasis and explicit clearing | Import/export/reset remain P2. |
| A48–A49 | Profile-owned scheduled tasks: search/filter, details, create/edit, templates, model/delivery choices, pause/resume/run/delete and recent run conversations | Hermes executes schedules. One-time completion may remove the task. Script-only tasks may have no conversation. No Android scheduler or new notification subscription is created. |

## MCP connection failures

Add MCP connector keeps its draft, including credentials, only in the open form.
Back and instance changes require discard confirmation when the form has edits;
profile selection offers the same confirmation before replacing the editor with
the selected profile. Cancel retains the draft and its owner. Pending setup blocks
navigation until the request settles. No draft credentials are saved on the device.

Verified the stock API against upstream main commit
`a566d20d226a8e2ef0747639dc8a3fc1c43f9dba` on 18 September 2026.
The profile-scoped [test route](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/hermes_cli/web_routers/mcp.py)
returns HTTP 200 with `ok: false`, `error` and an empty tool list when a probe
fails. OAuth start and polling return a [flow snapshot](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/tools/mcp_dashboard_oauth.py)
with `status: error` and `error` when sign-in fails.

Wing displays those reasons in the existing error notices, redacting URL
credentials/query strings, authorization/cookie headers and credential
assignments. A new probe clears the previous successful capability result.
`test/administration_mcp_test.dart` covers immediate and polled failures, profile
scope, redaction, successful-then-failed probes, and both themes at normal and
enlarged text. These fixtures establish error reporting, not successful sign-in
to a particular deployed connector; that requires its actual server response.

Reload uses the same upstream revision's strict
[`ReloadMcpParams` contract](https://github.com/NousResearch/hermes-agent/blob/a566d20d226a8e2ef0747639dc8a3fc1c43f9dba/tui_gateway/contracts/tools_mcp_plugins.py):
the server-wide `reload.mcp` command accepts `session_id`, `confirm`, `always`
and `rev`, but no `profile`. Wing asks once in a client dialog and sends
`confirm: true` in its single request after consent. It does not set `always`
or change the server's approval policy. The previous
profile-scoped call added `profile: default`, which stock parameter validation
rejects before reloading. Reload errors now retain the redacted server reason;
timeouts and disconnects report an uncertain outcome without automatically
retrying. The recovery tests enforce the single-confirmation contract and
cancellation before any request is sent.

## Scheduled tasks

Open Profile / Scheduled tasks to manage the selected profile's routines. Each
task shows its next run and state. The overview chooses the earliest eligible
server timestamp separately from running/attention ordering. Its latest-run summary
covers only tasks still listed; an ended conversation does not establish success. Tap it for instructions, delivery, model,
last-run details and recent runs. Search and All / Active / Paused /
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

Recent runs starts with 20 records and can expand to the latest 100. Agent
conversation records open the scoped chat. Script-output records show the
returned status title, timestamp and output/error preview inline; they do not
open a conversation. This includes output documents, terminal execution-ledger
records and latest-run metadata. The mixed-history contract was checked against
stock upstream `8d30c4eaabd85edb77a02fef6c5388d9344ef80c` on 30 September 2026.
Failures remain distinct from an empty history. No task-specific Stop command,
script upload, workflow builder or unlimited history is provided.

## Provider recovery

Provider details now offer **Renew access**, **Sign in again / Sign-in options**,
**Check status**, and a source-specific removal action. Implemented entirely in
Wing against stock Hermes `9dda4332f80c66994fe0e21197a8065a73a88991` (18 September
2026).
Renewal supports identified Anthropic/Claude, Nous device-code, Codex and xAI OAuth
credentials through the scoped stock console. Multiple identifiable matches need
an explicit choice. Other providers retain their supported sign-in/key workflow.

Hermes-managed OAuth removal uses the profile-scoped API and discloses that it
clears the provider's saved sign-ins. Claude Code file removal requires a reviewed
server path, explicit shared-file confirmation and permission from Hermes' file
API. It does not revoke the provider account, remove keychain credentials or clear
copies already in use. Unknown sources never receive an inferred deletion action.
No real provider credentials were changed during automated verification.

## Ownership and credentials

Profile / Provider access targets the selected profile, including `default`.
The Server tab and shared-account redirects have been removed.
An omitted or `current` profile can mean the dashboard's
launch home; use explicit canonical profile identity for credential operations.

The target ownership contract places accounts, keys and model defaults under
Profile. Current upstream no longer falls back to root `auth.json` when a named
profile lacks credentials.
Credential sources still differ by provider: external CLI accounts and explicit
shared-store mechanisms must be described according to verified backend behavior.

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

Analytics and administration routes borrow the workspace's captured server adapter.
Its sign-in and HTTP pool survive route re-entry; leaving a screen disposes only
its presentation/session observers. The workspace alone retires the adapter.
This prevents repeated screen visits from exhausting Hermes' password-login
admission. Explicit Refresh reloads failed sections and preserves last successful
sections during a subsequent failure. The auth/admission and HTTP recovery
contracts are exercised by `test/analytics_content_test.dart` and
`test/usage_analytics_session_test.dart`; response/lifetime behavior requires
controlled I/O tests, beyond checking constructor spelling in source.

Usage supports **1D, 7D, 30D, 90D and 365D** using profile-scoped model and daily analytics reads plus a separately cached year-wide daily read. A single scrollable band of week columns browses a year ending at the latest returned server date. Previously loaded periods are cached while the page remains open, and Refresh reloads year and period data. Day/grouping/measure selection makes no network requests. Daily model history and daily API-equivalent costs are explicitly unavailable; the daily token-type chart is supported. Stock Hermes filters a rolling N × 24 hours, then groups session starts by server-local calendar date with per-row DST handling. It supplies no timezone or calendar cutoff dates. Wing preserves all returned date keys, including adjacent-year dates; trend counts span those keys and gaps between them have zero returned usage. Calendar padding outside the year response's recorded date span is unknown, with no invented zero counts. A separately loaded period can extend the grid without replacing year counts with period counts. The outline surrounds the continuous span from the first through the last date returned for the selected period, including zero-usage days and gaps between returned dates. It does not infer calendar boundaries beyond that span. First and last dates may be partial; daily records exclude auxiliary usage included in model totals. This contract was checked against stock upstream `8d30c4eaabd85edb77a02fef6c5388d9344ef80c` on 30 September 2026.

For `openai-codex` only, Wing multiplies the already-uncached input, cached input and output counters by the direct OpenAI API base rates downloaded from models.dev, shared with the model picker and matched by exact model ID even for historical models no longer selectable. Output includes reasoning; it is not charged again. Other providers, including paid OpenAI API routes, retain Hermes's estimate. This rule uses provider identity, never a zero cost or model-name prefix.

Subscription-only history shows **API-equivalent cost**. Mixed history shows **Estimated usage value**, with Hermes and subscription subtotals. Composition bars use these same displayed values. Model rows combine matching model IDs across providers after valuing each contribution, and are ordered by the selected token/cost amount. Rows are passive; the individual model details sheet has been removed. A positive value below one cent displays **< USD 0.01**. Missing model prices or any of the three required counts stay unavailable; partial totals are identified and unpriced models remain visibly unavailable. Separate rows returned by Hermes (including auxiliary calls) each contribute once; Wing does not add the endpoint's totals again.

These estimates apply the current models.dev direct OpenAI API base rates to the selected history; they are not invoices or historical price reconstruction. Cache-write charges, long-context premiums and service-tier adjustments are excluded and disclosed on the screen. Hermes groups primary usage by the session's model/provider and filters sessions by start time, so mixed-model sessions and period boundaries inherit those upstream limitations.

`ProfileModelCatalog` combines the scoped stock catalog with `ModelsDevPricing`'s app-wide anonymous public rate read. `ModelsDevPrices` selects only the direct OpenAI API entries, and `ModelPrices` preserves their numeric precision for both screens. Backend prices on other picker routes remain route-specific. Analytics values only `openai-codex` this way; it requires all three rates and counts, with no alias or reseller matching. It retains rates for historical models outside today's picker. A download failure preserves tokens and Hermes estimates; cached rates remain usable with an explicit notice, while an empty cache leaves subscription estimates unavailable. Device-cached prices revalidate after six hours; Refresh requests both the backend catalog with `refresh=1` and public-rate revalidation. No bundled price asset or backend modification is required.

The stock pricing contract was inspected at upstream main `8bff64d6ed3414a66976bfa8ab72c14b6bca2a6f` on 9 October 2026 (`hermes_cli/web_routers/models.py`, `hermes_cli/inventory.py`, `hermes_cli/models_pricing.py`). That backend observation alone does not supply the direct API rates needed for Codex valuation. Wing's shared public models.dev reader supplies them independently; missing exact-ID rates remain unavailable. `models_dev_pricing_test.dart`, `usage_cost_test.dart`, `usage_analytics_test.dart`, `usage_analytics_session_test.dart` and `administration_usage_test.dart` guard shared decoding, absence, failure/recovery and retirement. See [model and pricing ownership](MODEL_CATALOG.md#shared-pricing-observations).

Render the actual Usage screen with `CAPTURE_USAGE=true` and `CAPTURE_FONT_DIR` pointing to Flutter's `bin/cache/artifacts/material_fonts`; `test/administration_usage_test.dart` writes captures to ignored `build/usage-review/`.

## Backend limits and verification

Memory edit/delete needs stable IDs and safe concurrent writes. Per-tool MCP mutation needs a contract that does not replace an unchecked whole map. Arbitrary-owner credential-pool detail and exact retained-file sizes are unavailable. These restrictions do not block independent browsing, enablement or supported settings.

Recorded native acceptance against Hermes 0.21.2 includes real profile lifecycle, settings readback, temporary credential-source changes and MCP operations using disposable data. Provider account approval, real inference for every route, SDK installation and backend self-update are not established by that run. See [Testing](TESTING.md) and [upstream bugs](UPSTREAM_HERMES_BUGS.md), including the Windows MCP profile-deletion failure.

Backend update checks also supply the read-only **Changes in this update** screen. It shows the returned commit summaries in server order, dates when available, optional authors and commit IDs, and a partial-history count when fewer commits are returned than the backend is behind. The stock API returns at most 20 summaries. Missing details do not block updates; opening the captured changelog makes no extra request.

## Health alerts

Open Menu → Hermes health → Alert settings (the outlined bell row above Host).
Settings apply on this device across active connections. RAM and disk warn
strictly above 90% for two minutes and clear strictly below 85% for two minutes.
CPU is off initially; its editable defaults are 95%, 80% and three minutes.
The device-wide Health alerts switch leads the page, followed by grouped Host
thresholds, Server & profile, and When an issue arrives controls. Host rows show
the warning threshold and duration alongside the independent native-critical
state; open a row for recovery limits and full trigger explanations.
The compact editor reads “Alert after [minutes] if above [percent]” and
“Clear after [minutes] if below [percent]”. Warning and recovery durations are
independent, accept 1–30 minutes, and preserve decimal percentages. Existing
shared durations are copied into both fields in the approved one-time local migration.
Memory and disk editors have a separate “Native Hermes critical pressure alert”
toggle below a divider after the warning/recovery fields. The “Usage warning”
toggle controls only Wing's configurable thresholds; the native toggle controls
Hermes-reported critical pressure independently. Both native toggles start enabled
for fresh settings. Either mechanism can remain enabled while the other is off.
Native critical pressure alerts immediately, even if its percentage is unavailable.
Memory's fixed trigger is below 5% available RAM or 64 MiB free. Disk's fixed
trigger is below 256 MiB free, or at least 95% used with under 1 GiB free.
These toggles control Wing's alerts on this device, not Hermes' classifications.
The new saved rule format requires the native-toggle field; earlier settings
without it are unreadable and alerts stay disabled until reconfigured. No new
compatibility migration is applied.
Toggles and valid threshold edits save automatically. Back and closing the compact
editor need no confirmation or Save action. Invalid numeric text does not replace
the last valid rule. The clear percentage must be lower than the alert percentage;
an overlapping pair shows both entered values in the error. For example, an alert
above 50% can clear below 45%, but cannot clear below 85%. Correct either field
and the valid pair saves automatically. The settings owner composes rapid edits
and serializes writes,
which continue after leaving the screen. Failed writes retain the selected values
for an icon-only retry while the confirmed policy remains active. Damaged local
settings disable collection until repaired through an edit or retry. None of these
settings modifies a Hermes profile.

Wing watches while foregrounded with a mounted workspace, or while the existing
background task monitor is active for that connection's ongoing work. It neither
starts a new Android service nor keeps monitoring alive on its own. The shared
host owner coalesces 15-second reads; the evaluator reacts to observations rather
than polling another cache. Background pauses retain pending warning and recovery
progress while the connection owner remains alive. Returning requests a fresh,
coalesced host read before either raising or clearing an alert. The maximum gap
between confirming readings is three times the applicable configured duration:
three times **Alert after** while raising and three times **Clear after** while
recovering. Equality retains progress; a longer gap starts a new period. The gap
is measured from the latest confirming reading, while elapsed time is measured
from the first reading in that period. For a one-minute warning, above-threshold
readings at 00:00, 00:30 and 01:00 raise the alert even when Wing backgrounds
between reads; returning after two minutes can raise it on the fresh reading,
but a gap over three minutes restarts the period. This infers continuity between
nearby readings; it does not observe usage while collection is paused. Failed or
unknown readings break pending progress. Existing issues remain qualified as
last known while paused or unknown. Profile checks and server connection status
come from their existing owners. Doctor and security-audit findings never generate
health alerts; they remain available in Health. The watcher never launches
diagnostics.
Connection notices stay quiet during transport interruptions and automatic
recovery. “Connection needs refresh” appears only when every active recovery has
stopped and a failed recovery left the connection unavailable, requiring a manual
refresh. This includes exhausted startup retries and failures that cannot be
retried automatically, such as rejected sign-in or certificate verification.
Application foreground entry starts a fresh connection recovery before admitting
health alerts, including while global Alert settings covers the workspace. Android
can block idle background connections; exhausted retries during that suspension
do not justify a new manual-refresh notice before foreground recovery runs.
Starting another recovery burst or restoring connection availability removes the
incident. A chat-only failure on a healthy connection does not create a global
connection notice or turn a later transient interruption into one.
Older recorded findings remain qualified as last known. Open Health to investigate
or request a fresh check. This is a warning about current Hermes usage, not an
always-on server monitor. Thresholds and qualified notices do not predict OOM.

A bell occupies the title row on every screen and appears while unresolved
issues remain, including qualified last-known findings. It rings once for a new
issue/escalation and respects reduced motion.
A brief notice is optional; alerts never auto-open a modal. Notices float below
the toolbar with generous clearance, 24 dp side gutters and a 360 dp width cap.
The neutral raised surface uses a small warning/critical icon, a readable title,
the triggering usage and rule, and a subordinate connection name. For example,
“93.4% used · above 90% for 2 min” shows the reading that admitted the occurrence.
Later readings update the issue's detail without replacing these trigger values;
escalation or recurrence captures new values. Critical alerts instead show
“critical pressure reported” with the supplied percentage, or “Usage unavailable”
when absent, because critical pressure bypasses the percentage/duration rule.
Non-resource notices have no numeric trigger line. The details dialog labels
the same retained values “At alert”. Text wraps at enlarged sizes; the icon-only
dismiss target remains 48 dp. Tap the notice to open alerts, or dismiss it while
retaining the issue in the bell. It expires after 5.5 seconds and respects reduced
motion. Tap the bell for one
issue at a time, ordered by severity, with browsing arrows when needed. The
dialog offers Close and Open Hermes health; it has no acknowledgement or snooze
actions. Closing it leaves the issue, count and severity-coloured bell visible.
Recovery removes the issue; recurrence/escalation starts a new occurrence and can
animate the bell and show a brief notice again.
The modal links to Hermes health, and configuration stays on Health's settings
row. No notification permission is requested for these in-app alerts.

The stock endpoints and pressure semantics were reverified on 10 October 2026
against upstream `b56a10246e81e23d10bf6f49ae176c082db53ed9`, including
`hermes_cli/web_routers/status.py`, `gateway/memory_status.py` and
`gateway/disk_status.py`. No backend change or alternative endpoint is used.

Ownership is mapped in [ARCHITECTURE.md](ARCHITECTURE.md). The regressions in
`test/health_alerts_test.dart` cover independent native/warning admission and
polling, strict native-toggle persistence, duration, hysteresis, unknown data, escalation,
independent durations, ordered autosave/retry, approved migration
preservation/failure, diagnostic exclusion and inactive late reads. Timestamped
regressions cover three-times-duration gaps at and beyond the limit, sliding
retention, repeated 30-second background pauses, independent recovery retention,
and fresh-response admission when another host consumer keeps polling. These
temporal and asynchronous properties require behavioral tests; a static source
guard cannot establish which reading confirms a period or when it expires.
`test/health_alerts_ui_test.dart` covers activity admission, shared title alignment,
conditional bell, Health navigation, focused details and immediate settings persistence in
both themes at normal and 320 dp/200% text, plus quiet foreground return and
connection notices gated by stopped recovery. Its overlapping-threshold regression
protects the specific validation message, retention of the saved rule and persistence
after correction; static checks cannot establish this input/error/save journey.
`server_connection_status_test.dart`
and `profile_workspace_controller_test.dart` cover multiple recovery owners,
stale chat failures, exhausted startup/live retries and refresh recovery.
`app_notification_routing_test.dart` covers app foreground recovery beneath global
Alert settings, admission before notices, preserved drafts and genuine continuing
outages. These
are behavioral guards: a static source rule cannot establish retry completion or
the ordering of transport loss, foreground return and recovery publication.
Layout depends on rendered metrics,
not a source pattern; these behavioral checks guard title geometry. Run with
`CAPTURE_ALERTS=true`, `CAPTURE_FONT_DIR=<font directory>` and
`CAPTURE_ALERT_DIR=<private output directory>` to inspect Flutter captures.

`integration_test/health_alerts_native_test.dart` exercises the actual Wing app
and routes on a disposable Android emulator with synthetic health observations.
It checks the one-shot bell motion, notice, focused modal, Health/settings
navigation, persistence and native-keyboard action reachability in both themes.
It also verifies a nonempty working Recents session whose search result resolves
to a compression successor, plus Analytics failure and explicit Refresh recovery
while host observation remains active. It uses bounded frame pumps because
ongoing-work animation deliberately never settles. These transport fixtures
establish Android behavior; authenticated read-only probes establish live data
contracts separately.
Run once at the ordinary Android viewport/font size, then at 320 dp with Android
font scale 2 and `--dart-define=ALERT_EXPECT_LARGE=true`. Do not override the
Flutter test viewport: this journey verifies the Android-provided constraints.

For the threshold lifecycle case alone, run that integration target with
`--dart-define=ALERT_RETENTION_NATIVE=true`. It uses real one-minute warning and
two-minute recovery durations, 46.2%/25% memory observations and no ongoing chats.
An emulator-only host controller reads the development package's
`code_cache/wing-health-retention-stage.json`. For each new token, it captures the
Android window or presses Home, waits the requested `seconds`, then reopens the
same app process; acknowledge the completed action by writing that token to
`code_cache/wing-health-retention-ack`. Checkpoints have bounded deadlines.
The journey requires a fresh host reading on each return, no host polling while
paused, an alert after two 30-second pauses and recovery after a two-minute pause.
It tests the shipped lifecycle/alert owners with controlled transport responses,
not the physical phone's process retention or live Hermes readings. Keep native
captures, source hashes and checkpoint receipts under ignored `build/`.

| Before | After | Why |
| --- | --- | --- |
| Chats and conversation vertically center title and scope in different-height toolbars | Shared 48 dp title row, optional scope row below | Bell and titles share one compact geometry |
| Administration moves its enlarged title into the content | Title remains in the shared header and grows | Consistent title position and reachable actions |
| Each viewer/header measures its own toolbar | WingAppBar owns geometry; viewers delegate | One reusable layout owner |
| Alert settings has a generic tune icon | Outlined bell on Health's navigation row | Matches the feature's attention cue |
