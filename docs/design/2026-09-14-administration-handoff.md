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
| Health / Server | Runtime/launch-profile observations, bounded logs, Doctor/security audit and action results |
| Health / Profile | Scoped readiness and usage; recovery links to the owning editor |

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
Profile / Access and connectors. Shared-account links within the provider editor
still target `default` and need correction together with its shared-account labels. Removing profile credentials must not promise restored root
access. External CLI ownership remains distinct. Show credential provenance only
when the backend establishes it, and do not infer account use from provider names.

Runtime health uses `profiles/active.current`, resolved through profile metadata. `active` is the sticky future-launch selection, not the runtime identity. Neither it nor the mobile selection may substitute for `current`. Unknown identity is shown as unavailable while independent server/runtime operations remain reachable.

The owner-approved 18 September Health layout uses Server and Profile groups,
with no combined health verdict. Doctor, audit and Logs remain server-owned;
Usage and five observation rows follow the header-selected profile. Unknown
coverage is local, configuration does not expire after five minutes, and actual
credential expiration remains visible. The Profile refresh icon explicitly checks access
without inference. Details show their captured scope and link to the owning editor.
See [Health observations](../ADMINISTRATION.md#health-observations) for the current
stock API verification and rendering contract.

Verified against stock upstream `98f758ae7e8db83c2bb9214c3b35adf41df15f03` on 17 September 2026: explicitly profile-scoped `setup.status` observes provider configuration without creating credentials. See the [implementation and source evidence](../ADMINISTRATION.md#health-observations).

## Edits and state

Capture connection and canonical profile identity when opening an editor. Keep that target fixed and visible while editing. Selection changes or late responses must not redirect a save. Display-name changes do not change canonical identity. A missing profile should not disable unrelated Versions & updates or runtime Health views.

Distinguish pending, stale, unavailable, offline, failed, uncertain and partially successful results. Keep edits after an unconfirmed save and show last-checked information for stale observations. Do not expose endpoint/PID bookkeeping in ordinary UI.

Toolset enabled/configured/platform are separate facts. Missing cached MCP runtime status means unknown, not disconnected; explicit Test is separate. Show returned tools and prompt/resource counts. Memory budgets use characters. Memory edits/deletes and per-tool MCP writes remain unavailable until their concurrency contracts are safe. A review screen does not fix positional IDs or whole-map writes.

Skill updates state their group scope. Auxiliary reset-all discloses clearing endpoint credentials. Defaults distinguish saving configuration from adopting it in a running session. Setup/install/diagnostic actions retain target and returned action identity, and require actual results before claiming completion.

The selected narrow advanced portions are agent-plugin inventory/toggles, basic compression, redaction/private-URL/checkpoint controls, supported backend voice defaults and settings search. Plugin installation/lifecycle, context engines, browser-profile permissions, model installation and settings import/export/reset remain outside those narrow slices. No remote TUI restart, automatic repair or P2 expansion is implied.
