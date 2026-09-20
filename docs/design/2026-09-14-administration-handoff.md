# Administration ownership and design

This is the ownership contract for Administration, updated on 17 September 2026 to use a tab-free Profile root and a standalone Health destination, with versions in the global menu, and provider ownership corrected to follow the latest-upstream policy in [AGENTS.md](../../AGENTS.md). Use the shared [Studio tokens](../DESIGN_SYSTEM.md). [Administration](../ADMINISTRATION.md) lists implemented controls and backend limitations; the [roadmap](../ADMINISTRATION_ROADMAP.md) owns feature scope. Generated mockups are not evidence of implemented backend operations.

## Navigation

| Destination | Owns |
| --- | --- |
| Profile / Defaults | Main model/provider, supported reasoning/speed, auxiliary assignments and fallback models |
| Profile / Identity | Description and SOUL; Manage profiles at the end of the scrolling selector for lifecycle |
| Profile / Memory | Search/read, enablement and character budgets; unavailable edit/delete until safe IDs exist |
| Profile / Skills and tools | Installed skills, provenance, instructions, usage, local edits/archive, Hub, toolsets and a distinct agent-plugin page |
| Profile / Scheduled tasks | Per-profile schedules, task editing/templates, execution actions and recent run conversations; connected-server delivery discovery |
| Profile / Access and connectors | Profile provider accounts and API keys, observed credential sources and profile MCP configuration |
| Profile / Behavior | Supported execution limits, approval policy, basic compression, reach/recovery policy and backend voice defaults |
| Profile / Manage profiles | Collection lifecycle; compact pill after the last profile, scrolling with the profile selector |
| Global menu / Connection and Server version | Icon, connection name and LED open connection details; server version opens Versions & updates and checks upstream availability. Client version remains in App settings. |
| Health / Server | Bounded logs, Doctor/security audit, Run all diagnostics and action results |
| Health / Profile | Scoped readiness; recovery links to the owning editor |
| Global menu / Hermes analytics | Profile-scoped usage, tokens, estimated costs and history |

MCP connectors owns Reconnect MCP tools, with confirmation that it reconnects tools across all server profiles and can invalidate prompt caches. Versions & updates contains server identity and update controls. Only the server has an upstream update check and circular-arrows availability indicator. Check update progress appears after an update request; it reads the running update action, while Check for updates compares installed code with upstream.

Keep the Profile root short. The global menu opens the dedicated Hermes health destination; there are no ownership tabs. Use categorized rows and drill-downs, sheets for short choices and dedicated screens for inventories and long editors. Search results identify the owner and navigate to the single editor. Health links to settings; it does not duplicate their forms.

The owner approved scheduled-task implementation on 17 September 2026 and asked
for a polished, focused surface independent of a future administration redesign.
Its dedicated list/detail/editor uses Studio tokens, a prominent next-run line,
readable instructions and reachable actions. Do not expand this change into
restyling the other administration destinations.

Keep the connection visible on Profile and Health. Health uses the shared header for profile selection. Server writes must not appear profile-scoped. Android appearance, notifications, dictation/playback and composer preferences stay in App settings.

## Account and runtime identity

Provider accounts, API keys and model choices belong to the selected profile,
including the canonical `default` profile. Upstream removed automatic root
`auth.json` inheritance in commit `93889b7` on 16 September 2026 UTC. A blank
profile needs provider access configured; cloning can copy API keys and settings,
which is separate from inheritance. See the [verified ownership research](../research/2026-09-17-hermes-provider-ownership.md)
for source evidence and provider-specific external/shared credential mechanisms.

The Server / Providers entry has been removed; provider searches route to
Profile / Access and connectors. Provider recovery now removes the obsolete shared-account links and labels;
its actions retain the selected canonical profile. Removing profile credentials
does not promise restored root access. External CLI ownership remains distinct. Show credential provenance only
when the backend establishes it, and do not infer account use from provider names.

The owner-approved 19 September Health update removes runtime-profile metadata
and uses a Server refresh icon for Run all diagnostics, with the same progress
spinner as Profile. Diagnostic detail pages use a top-bar play action to rerun,
with automatic result polling and no bottom rerun button. Doctor and security
audit use their existing server endpoints, with separate retained progress and
results. They do not accept the selected mobile profile. Confirmations and result
headers identify the connection, and Logs no longer requests profile identity.

The owner-approved 18 September Health layout uses Server and Profile groups,
with no combined health verdict. Doctor, audit and Logs remain server-owned;
Four observation rows follow the header-selected profile. Usage now lives in the
standalone Hermes analytics drawer destination, below Hermes health. Unknown
coverage is local, configuration does not expire after five minutes, and actual
credential expiration remains visible. All four Profile rows reuse saved results on entry and profile selection.
A missing or 24-hour-old profile refresh triggers fresh checks. Server results
and per-profile snapshots survive app restart; expired completed server diagnostics
refresh on Health entry; missing results trigger the initial run.
The Profile refresh icon repeats credential, tool setup, connector and task checks.
Healthy Tool setup, Connectors and Scheduled tasks rows are passive, with green icons
and no disclosure arrow. Other results retain details with their captured scope
and links to the owning editor.
See [Health observations](../ADMINISTRATION.md#health-observations) for the current
stock API verification and rendering contract.

The 19 September correction removes the Model & provider detail destination.
Model access is an inline Health observation, with result and model/provider.
The Server and Profile headings own check times; overview rows do not repeat them.
Counts describe enabled tool groups and setup gaps, connector connection checks,
and listed tasks with reported errors. What’s checked? explains the four checks
without promising test messages, successful tool calls or successful job runs.
Healthy and unchecked states have no actions or navigation. The Profile
refresh runs the check. Only problems reveal recovery: Fix access/Review access
opens the captured profile's provider editor, Retry reruns the check, and server
access rejection offers Review connection. Model choice and routine account
management remain in Administration. The stock runtime check can resolve a
configured fallback, so any different model/provider is named without validating
the selection. Replies and quota are not tested. See the
[verified check contract](../ADMINISTRATION.md#health-observations).

Verified against stock upstream `98f758ae7e8db83c2bb9214c3b35adf41df15f03` on 17 September 2026: explicitly profile-scoped `setup.status` observes provider configuration without creating credentials. See the [implementation and source evidence](../ADMINISTRATION.md#health-observations).

## Edits and state

Capture connection and canonical profile identity when opening an editor. Keep that target fixed and visible while editing. Selection changes or late responses must not redirect a save. Display-name changes do not change canonical identity. A missing profile should not disable unrelated Versions & updates or runtime Health views.

Distinguish pending, stale, unavailable, offline, failed, uncertain and partially successful results. Keep edits after an unconfirmed save and show last-checked information for stale observations. Do not expose endpoint/PID bookkeeping in ordinary UI.

Toolset enabled/configured/platform are separate facts. Missing cached MCP runtime status means unknown, not disconnected; explicit Test is separate. Show returned tools and prompt/resource counts. Memory budgets use characters. Memory edits/deletes and per-tool MCP writes remain unavailable until their concurrency contracts are safe. A review screen does not fix positional IDs or whole-map writes.

Skill updates state their group scope. Auxiliary reset-all discloses clearing endpoint credentials. Defaults distinguish saving configuration from adopting it in a running session. Setup/install/diagnostic actions retain target and returned action identity, and require actual results before claiming completion.

The selected narrow advanced portions are agent-plugin inventory/toggles, basic compression, redaction/private-URL/checkpoint controls, supported backend voice defaults and settings search. Plugin installation/lifecycle, context engines, browser-profile permissions, model installation and settings import/export/reset remain outside those narrow slices. No remote TUI restart, automatic repair or P2 expansion is implied.
