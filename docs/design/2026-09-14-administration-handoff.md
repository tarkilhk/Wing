# Administration ownership and design

This is the current ownership contract for the Profile, Server and Health design selected on 14 September 2026. Use the shared [Studio tokens](../DESIGN_SYSTEM.md). [Administration](../ADMINISTRATION.md) lists implemented controls and backend limitations; the [roadmap](../ADMINISTRATION_ROADMAP.md) owns feature scope. Generated mockups are not evidence of implemented backend operations.

## Navigation

| Destination | Owns |
| --- | --- |
| Profile / Defaults | Main model/provider, supported reasoning/speed, auxiliary assignments and fallback models |
| Profile / Identity | Description and SOUL; link to Server / Profiles for lifecycle |
| Profile / Memory | Search/read, enablement and character budgets; unavailable edit/delete until safe IDs exist |
| Profile / Skills and tools | Installed skills, provenance, instructions, usage, local edits/archive, Hub, toolsets and a distinct agent-plugin page |
| Profile / Scheduled tasks | Per-profile schedules, task editing/templates, execution actions and recent run conversations; connected-server delivery discovery |
| Profile / Access and connectors | Effective provider access, links to shared account owners, explicit credential overrides and profile MCP configuration |
| Profile / Behavior | Supported execution limits, approval policy, basic compression, reach/recovery policy and backend voice defaults |
| Server / Connection | Device-held endpoint/password/headers and connection test/repair |
| Server / Providers | Shared root provider accounts and owner-aware recovery |
| Server / Profiles | Collection lifecycle; opening an individual profile selects Profile |
| Server / Runtime | Backend identity/update and process-wide MCP reload |
| Health / Runtime | Runtime/launch-profile observations, bounded logs, Doctor/security audit and action results |
| Health / Selected profile | Scoped readiness and usage; recovery links to the owning editor |

Keep tab roots short. Use categorized rows and drill-downs, sheets for short choices and dedicated screens for inventories and long editors. Search results identify the owner and navigate to the single editor. Health links to settings; it does not duplicate their forms.

The owner approved scheduled-task implementation on 17 September 2026 and asked
for a polished, focused surface independent of a future administration redesign.
Its dedicated list/detail/editor uses Studio tokens, a prominent next-run line,
readable instructions and reachable actions. Do not expand this change into
restyling the other administration destinations.

Keep the connection visible across tabs. Profile selection belongs in Profile and the selected-profile section of Health. Server writes must not appear profile-scoped. Android appearance, notifications, dictation/playback and composer preferences stay in App settings.

## Account and runtime identity

Hermes supports root fallback for [provider state](https://github.com/NousResearch/hermes-agent/blob/e16f686706b1e0d5334fd1ae82190058d2a19694/hermes_cli/auth.py#L773) and [credential pools](https://github.com/NousResearch/hermes-agent/blob/e16f686706b1e0d5334fd1ae82190058d2a19694/hermes_cli/auth.py#L893). Shared accounts belong under Server / Providers. Profile keeps model choices, effective-source information and explicit overrides. This supersedes the early boards that placed all accounts under Profile; MCP remains profile-owned.

Target the verified canonical root explicitly for shared writes. Removing a profile override can restore shared access. Do not label it Disconnect everywhere or invent an affected-profile inventory. External CLI ownership remains distinct. Show credential provenance only when the backend establishes it.

Runtime health uses `profiles/active.current`, resolved through profile metadata. `active` is the sticky future-launch selection, not the runtime identity. Neither it nor the mobile selection may substitute for `current`. Unknown identity is shown as unavailable while independent server/runtime operations remain reachable.

## Edits and state

Capture connection and canonical profile identity when opening an editor. Keep that target fixed and visible while editing. Selection changes or late responses must not redirect a save. Display-name changes do not change canonical identity. A missing profile should not disable unrelated Server or runtime Health views.

Distinguish pending, stale, unavailable, offline, failed, uncertain and partially successful results. Keep edits after an unconfirmed save and show last-checked information for stale observations. Do not expose endpoint/PID bookkeeping in ordinary UI.

Toolset enabled/configured/platform are separate facts. Missing cached MCP runtime status means unknown, not disconnected; explicit Test is separate. Show returned tools and prompt/resource counts. Memory budgets use characters. Memory edits/deletes and per-tool MCP writes remain unavailable until their concurrency contracts are safe. A review screen does not fix positional IDs or whole-map writes.

Skill updates state their group scope. Auxiliary reset-all discloses clearing endpoint credentials. Defaults distinguish saving configuration from adopting it in a running session. Setup/install/diagnostic actions retain target and returned action identity, and require actual results before claiming completion.

The selected narrow advanced portions are agent-plugin inventory/toggles, basic compression, redaction/private-URL/checkpoint controls, supported backend voice defaults and settings search. Plugin installation/lifecycle, context engines, browser-profile permissions, model installation and settings import/export/reset remain outside those narrow slices. No remote TUI restart, automatic repair or P2 expansion is implied.
