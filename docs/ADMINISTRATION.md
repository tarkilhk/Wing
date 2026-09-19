# Administration

Administration opens directly on the profile overview without tabs. Hermes health is a dedicated destination in the global navigation. The selected server stays visible. Profile opens with a compact profile brief and current-value navigation: Models and reasoning, Identity, Memory and Behavior under Agent setup; Skills and tools, Access and connectors and Scheduled tasks under Capabilities and automation. Manage profiles is its own pill after the last profile in the horizontally scrolling selector. The global menu shows a larger Wing identity above a low server footer. The connection icon, name and LED open connection details; the server version opens Versions & updates. Back restores the open menu. Client version remains in App settings. Provider settings remain under Profile / Access and connectors. Version and upstream update availability load automatically; an update icon marks newer backend code. Health separates server diagnostics from selected-profile readiness. Hermes analytics is a separate drawer destination for usage history, tokens and estimated costs.

Read the [ownership handoff](design/2026-09-14-administration-handoff.md) before changing these flows. The [roadmap](ADMINISTRATION_ROADMAP.md) preserves selected priorities and exclusions.

Target correction, 17 September 2026: Wing follows the latest upstream Hermes as
specified in [AGENTS.md](../AGENTS.md). Provider credentials belong to profiles;
upstream removed automatic root `auth.json` inheritance. The Providers entry has
been removed from the Server tab and administration search routes provider queries
to Profile. Shared-account links and wording inside the provider editor still
reflect the older design and need a separate correction.

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
Returning from an editor refreshes only the affected observations and briefly emphasizes changed values;
reduced motion suppresses the emphasis. Health visits and search preserve profile
observations and scroll context. Search shows the full owner/editor/field path and opens the exact field without
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

## Health observations

Health has two groups. Server owns Doctor, security audit and Logs. Its refresh icon
starts Doctor and security audit together, without opening their details or a
confirmation dialog. It is disabled while either diagnostic is starting, running
or has an uncertain completion. Each operation retains its own result; a failed
start does not prevent the other operation from running. The icon shows a spinner
while diagnostics start or run, matching Profile refresh.
Doctor and security audit details rerun from their top-bar play action, with no
bottom rerun button; result polling remains automatic. There is no runtime-profile
label. Diagnostic confirmations and results identify the server. Profile uses
selection from the shared header,
a refresh icon beside its heading, four stable rows (Model access, Tools, Connectors,
Scheduled tasks). There is no global health verdict. Optional server
diagnostics say Not run until explicitly started.

Health owns its profile observations, so opening Administration first is unnecessary.
Opening Health or selecting a profile reuses that profile’s saved results for 24 hours.
A profile with no saved refresh, or one at least 24 hours old, automatically checks all four rows:
model credential resolution, enabled-tool configuration, enabled connector connection
probes, and scheduled-task errors or uncertain actions. The Profile refresh icon and
pull-to-refresh repeat the same checks. Returning from provider recovery also checks
again. Pending refreshes are shared per profile; another profile can refresh immediately,
and late results remain attached to their captured scope. No model prompt is sent.
Model access is a passive row directly in Health. It shows credential status,
model/provider and the check time. There is no model/provider detail destination,
Change model control, routine account-management shortcut, or row navigation.
The Profile refresh icon repeats the checks. A reported provider failure
reveals Fix access, which opens the profile's existing account editor; an
unconfirmed alternate route offers Review access. An incomplete check offers Retry,
and server authentication rejection offers Review connection. Healthy and unchecked
states have no recovery actions. A quiet note distinguishes credentials from replies
and quota. Observation timestamps belong to their results, not a group-wide verdict.

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

On Health entry, each completed server diagnostic at least 24 hours old runs
again automatically; diagnostics never run before their first explicit start.
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
Unrecognized or truncated output never implies no vulnerabilities. See the
[audit report contract](research/2026-09-18-security-audit-report.md).
Stock Hermes exposes no remote Doctor repair action, so Wing adds none.
Each Doctor finding has an **Ask Hermes** action that opens a new chat using the
selected profile, with that finding and the available diagnostic log in an
editable, unsent draft. The prompt asks for an explanation and proposed solution,
including data-loss risks and verification, and says not to make changes or run
repairs yet. The user reviews and sends it. Doctor output is requested up to the
stock limit of 2,000 lines / 256 KiB; it is not guaranteed to be complete. See the
[per-finding design and API verification](design/2026-09-18-doctor-summary.md#ask-hermes-about-a-finding).

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
and partial coverage is stated. See the [usage dashboard](design/2026-09-18-usage-dashboard.md)
and its [stock API boundary](research/2026-09-18-usage-redesign-data-contract.md).
Logs keeps server source, severity, submitted text search, a 100-line limit and
explicit empty/error states.

## Current controls

| Roadmap | Implemented surface | Boundary |
| --- | --- | --- |
| A01–A02 | Existing main-model editor; capability-gated reasoning and speed defaults | Defaults apply to new sessions. Model identity is rechecked before reasoning/speed saves. Unsupported flags do not create controls. |
| A03–A06 | Existing individual skill/tool toggles and inventories, reached from Skills and tools | Configured, enabled and platform remain distinct. Toolset enablement can start backend setup; it is not proof of readiness. |
| A07 | Searchable retained-memory list and complete detail | Read-only; generated positional identity is used only for reads. |
| A08 | Explicit unavailable state | Edit/delete requires a stable identity and concurrency-safe backend contract. No memory mutation is sent. |
| A09–A11 | Shared and profile access inventories, source labels, stored-key management, supported device-code sign-in, cancellation, disconnect | External CLI login remains external. Pool-account detail cannot be safely attributed to an arbitrary selected owner; it is explicitly unavailable. No credential values are fetched for display. |
| A13 | Auxiliary assignments, automatic choice, reset-all, unavailable-model warning, expensive-model confirmation | Reset-all discloses endpoint-credential clearing. Readback must match the affected tasks. |
| A14 | Ordered fallback list with add/remove/reorder, schema-supported agent/subagent execution controls | Fallback edits check for an already-changed list and verify the saved result. Non-object entries are shown as invalid instead of blocking the list; they remain unchanged until explicitly removed. Custom provider definitions remain P2. |
| A16 | Dedicated full-screen description/SOUL editor under Identity | Uses the captured profile gateway; existing readback behavior is retained. |
| A17 | Create, clone configuration, rename and delete through the trailing Manage profiles pill in the Profile selector | Default profile has presentation-only rename and no delete action. Creation/rename/deletion is followed by discovery. Unconfirmed outcomes remain unconfirmed. Full-data/channel cloning and optional multi-step setup are not offered. |
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

Profile / Provider access targets the selected profile, including `default`.
The Server tab has been removed. The provider editor still exposes
shared-account links targeting `default`; those links need correction alongside
its inheritance wording. An omitted or `current` profile can mean the dashboard's
launch home; use explicit canonical profile identity for credential operations.

The target ownership contract places accounts, keys and model defaults under
Profile. Current upstream no longer falls back to root `auth.json` when a named
profile lacks credentials. The UI's existing inheritance claims need correction.
Credential sources still differ by provider: external CLI accounts and explicit
shared-store mechanisms must be described according to verified backend behavior.
See the [ownership research](research/2026-09-17-hermes-provider-ownership.md) for
the exact upstream change, API limits and source-specific exceptions.

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

Usage supports **1D, 7D, 30D, 90D and 365D** using profile-scoped model and daily analytics reads plus a separately cached year-wide daily read. A single band of week columns browses that year with earlier/later controls. Previously loaded periods are cached while the page remains open, and Refresh reloads year and period data. Day/grouping/measure selection makes no network requests. Daily model history and daily API-equivalent costs are explicitly unavailable; the daily token-type chart is supported. Daily records use UTC session-start dates and exclude auxiliary usage included in the model totals. A rolling N-day period can span N+1 UTC dates. The stock API and these limits were checked at `c62bd9f2078a946108f1c9d9b24bf118963277ef` on 18 September 2026.

For `openai-codex` only, Wing multiplies the already-uncached input, cached input and output counters by published standard OpenAI API rates. Output includes reasoning; it is not charged again. Other providers, including paid OpenAI API routes, retain Hermes's estimate. This rule uses provider identity, never a zero cost or model-name prefix.

Subscription-only history shows **API-equivalent cost**. Mixed history shows **Estimated usage value**, with Hermes and subscription subtotals. Composition bars use these same displayed values. Model rows combine matching model IDs across providers after valuing each contribution, and are ordered by the selected token/cost amount. Rows are passive; the individual model details sheet has been removed. A positive value below one cent displays **< USD 0.01**. Missing model prices or any of the three required counts stay unavailable; partial totals are identified and unpriced models remain visibly unavailable. Separate rows returned by Hermes (including auxiliary calls) each contribute once; Wing does not add the endpoint's totals again.

These are base-rate estimates at the bundled catalogue's current prices, applied to the selected history, not invoices or historical price reconstruction. Cache-write charges, long-context premiums and service-tier adjustments are excluded and disclosed on the screen. Hermes groups primary usage by the session's model/provider and filters sessions by start time, so mixed-model sessions and period boundaries inherit those upstream limitations.

Maintain [the bundled OpenAI catalogue](../assets/pricing/openai.json) by adding exact model IDs with all three USD-per-million rates, their official source URL and `verified_on` date. Check the standard/base rates in official OpenAI documentation; do not copy Fast/Batch rates or infer prices for similarly named variants. The initial catalogue covers Astra, Sol, Terra, Luna, GPT-5.5, GPT-5.4, GPT-5.4 Mini and GPT-5.3 Codex. Spark and unlisted variants show unavailable. Updating this file ships with the app and requires no runtime pricing service or server changes. Run `test/usage_cost_test.dart` and `test/administration_usage_test.dart` after updating it.

The stock pricing rule, model catalogue and analytics response were rechecked against upstream main **`d177b119e9c56c9ddc0b7379ffce52341ec06584`** on 2026-09-18. The [source investigation](research/2026-09-18-subscription-api-equivalent-cost.md) records the API and pricing evidence. Render the actual Usage screen with `CAPTURE_USAGE=true` and `CAPTURE_FONT_DIR` pointing to Flutter's `bin/cache/artifacts/material_fonts`; `test/administration_usage_test.dart` writes captures to ignored `build/usage-review/`.

## Backend limits and verification

Memory edit/delete needs stable IDs and safe concurrent writes. Per-tool MCP mutation needs a contract that does not replace an unchecked whole map. Arbitrary-owner credential-pool detail and exact retained-file sizes are unavailable. These restrictions do not block independent browsing, enablement or supported settings.

Recorded native acceptance against Hermes 0.21.2 includes real profile lifecycle, settings readback, temporary credential-source changes and MCP operations using disposable data. Provider account approval, real inference for every route, SDK installation and backend self-update are not established by that run. See [Testing](TESTING.md) and [upstream bugs](UPSTREAM_HERMES_BUGS.md), including the Windows MCP profile-deletion failure.

Backend update checks also supply the read-only **Changes in this update** screen. It shows the returned commit summaries in server order, dates when available, optional authors and commit IDs, and a partial-history count when fewer commits are returned than the backend is behind. The stock API returns at most 20 summaries. Missing details do not block updates; opening the captured changelog makes no extra request.
