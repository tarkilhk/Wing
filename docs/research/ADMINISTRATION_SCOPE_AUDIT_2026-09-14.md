# Administration scope audit

Research completed 2026-09-14 against the installed official Hermes checkout and the running local dashboard. Prototype C remains the selected design: Profile, Server, Health.

Provider-account interpretation corrected later on 2026-09-14: the owner's report of one login across many profiles prompted an [independent source recheck](PROVIDER_CREDENTIAL_SOURCE_RECHECK_2026-09-14.md) and [local structural observation](PROVIDER_LOCAL_STORE_OBSERVATION_2026-09-14.md). Shared root provider accounts belong under Server; Profile keeps provider/model choices, effective inherited access and explicit credential overrides. The original map below correctly records scoped write contracts but overgeneralized account ownership from those contracts. Shared recovery must not default to creating a profile-specific login. Read the updated [administration design map](../design/2026-09-14-administration-handoff.md) for corrected A09-A11 placement. Original source and 39-GET evidence remain unchanged.

## Decision

Keep the ownership split. Most settings belong under Profile, including model defaults, credentials saved for that profile, skills, toolsets, MCP configuration, agent plugins, memory, execution policy and backend voice settings. Server should be a smaller tab containing the profile collection and connection/runtime administration. Health reports both runtime and profile observations and must label which it is showing.

Do not move a profile setting to Server merely because its implementation runs on the server. Likewise, an endpoint with no profile argument often operates on the dashboard's launch profile. That does not make its data server-wide.

This is research and a proposed implementation contract. No expanded administration screen or backend fix was built.

## Evidence and limits

- Installed checkout: `C:/Users/rober/AppData/Local/hermes/hermes-agent`.
- Source HEAD: `e16f686706b1e0d5334fd1ae82190058d2a19694`. Source inspection found a clean installed checkout. This identifies the files inspected, not proof that every module in the running process was loaded from that exact revision.
- Running dashboard inspected at `http://127.0.0.1:51163`, Python PID 26840. Authentication used the existing dashboard session-token flow, with the token kept in memory.
- [Sanitized live observations](ADMINISTRATION_LIVE_READS_2026-09-14.json) contain 39 GET results: 32 successful reads, six expected 404 responses and one 500 response for an intentionally nonexistent profile.
- The three existing profiles were `default`, `android-qa-a` and `android-qa-b`. Installed skill counts were 84, 3 and 2; toolset counts were 29 each. All had zero configured MCP servers. Auxiliary-model inventory returned 11 tasks each.
- Scoped config, schema, model information, skills, toolsets, MCP inventory, learning graph and seven-day usage/model analytics all returned 200 for the three real profiles.
- Memory arrays contained zero, one and zero entries respectively. This validates empty and populated list shapes, not memory detail/edit behavior. Graph skill nodes and installed skill inventories are different lists.
- The nonexistent profile returned 404 for model information, config, skills, toolsets, MCP and usage. Learning graph returned 500, matching its broad exception handler. Never interpret that 500 as an empty memory list. [Learning routes][learning-routes]
- No mutation requests, inference, OAuth, MCP connection probes, setup, doctor, updates or repairs were invoked. GET handlers can perform their own cache or bookkeeping work; this audit does not claim the process made zero incidental disk writes.
- The report retains shapes, counts and public schema definitions. It does not retain actual configuration values, credentials, instructions, memory content, SOUL, logs or transcripts.
- WebSocket plugin/MCP operations, populated memory writes, external accounts and live adoption of settings were inspected in source only. Two-server isolation and Android device behavior remain implementation acceptance work.

The repeatable probe is [inspect_administration_readonly.py](../../tools/qa/inspect_administration_readonly.py). Run it against the current loopback dashboard port, which can change after restart:

```powershell
python tools/qa/inspect_administration_readonly.py --port 51163 --output docs/research/ADMINISTRATION_LIVE_READS_2026-09-14.json
```

## Ownership and transport rules

The backend resolves explicit named profiles into their own Hermes home. Omitted, empty and `current` scopes can mean the dashboard process profile. Its scoped configuration helpers use context-local home overrides; skill operations also retarget import-bound skill directories under a lock. Keep the canonical profile explicit. [Profile scopes][scopes]

The Android app already captures connection and profile in `ProfileGateway`. Extend that approach with separate profile-administration and server-administration interfaces using the existing authenticated transport. Capture ownership when an editor opens; a changed selection must never redirect the save. Keep scope in cache keys and reject late results for a different target. [Android connection manager][android-transport]

Scope belongs in the correct request location, not merely a query parameter appended to every request:

| Contract | Scope location |
| --- | --- |
| Config, model, skill/toolset toggles | Supported query and/or body; body profile wins where both exist. Send one consistent captured identity. |
| Learning-node edit/delete | Body `profile` is required to target a named profile. A query-only selector does not scope these writes. |
| Skill content edit/create | Body carries `profile`. |
| MCP gateway and plugin management RPC | `params.profile`. |
| Profile collection operations | Selected connection plus the named object in the path/body. No client-selected profile should redirect the operation. |
| Legacy ops, logs, credential pool, dashboard plugins | No arbitrary profile selector. Treat as launch-profile/runtime operations or mark unavailable for the selected profile. |

Sources: [config][config], [models][models], [skills][skills], [learning routes][learning-routes], [gateway tools][rpc], [ops][ops], [dashboard plugins][dashboard-plugins].

GET `profiles/active` distinguishes sticky CLI default `active` from process `current`. POST to it changes future CLI/gateway defaults, not the phone's local selection. The mobile selector must never call it. [Profile lifecycle][profiles], [Android scope ADR][scope-adr]

## P0/P1 operation map

"Supported" below means a source contract exists. It does not imply that live writes or Android UI acceptance passed in this audit. Mixed P1/P2 rows are split as a proposed scope interpretation, pending the build's feature checklist.

| IDs | Owning tab and operation | Contract and build boundary |
| --- | --- | --- |
| A01 | Profile / default model | GET `model/info`, GET `model/options`, POST `model/set` with `scope: main`, provider, model, profile. Preserve `confirm_required` and retry only after confirmation. Defaults apply to new sessions. Existing Android flow can be rehomed. [Models][models] |
| A02 | Profile / reasoning and speed | Sparse config writes for `agent.reasoning_effort` and `agent.service_tier`. Model-option capability metadata gates controls. Schema tier options alone do not prove that the selected model supports them. Reasoning is handled explicitly by Desktop and is absent from the sampled generic schema. [Desktop model controls][desktop-models], [config][config] |
| A03, A04 | Profile / installed skills | GET `skills`, GET `skills/content?name=...`, PUT `skills/toggle`. Keep server provenance and enabled state; load full instructions on demand. Existing Android screen can be reused. [Skills][skills] |
| A05, A06 | Profile / toolsets | GET `tools/toolsets`, PUT `tools/toolsets/{name}`. Keep enabled separate from configured. `available` is a legacy enabled alias. Platform means configuration context such as CLI or a messaging platform, not Windows/Linux. Enabling can start post-setup. [Toolsets][tools] |
| A07, A08 | Profile / memory list and correction | GET `learning/graph`, GET `learning/node?id=...`; PUT body `{id,content,profile}`, DELETE body `{id,profile}`. Source supports edits, but position-based memory IDs lack conflict protection. Read-only list can ship first; robust correction needs the concurrency issue below resolved. [Learning routes][learning-routes], [mutations][learning-mutations] |
| A09 | Profile / provider readiness | GET `providers/oauth?profile=...`, GET `env?profile=...`, model options and tool-specific config provide different readiness facts. Display their distinctions. Multi-account credential-pool REST routes have no profile selector and must not back an arbitrary profile's account list. [OAuth][oauth], [env][env], [credential pool][pool] |
| A10 | Profile / reconnect | Supported provider catalog entries use start/poll/cancel device-code flows with the captured profile. Honor returned flow type. External CLI providers remain external; the generic submit route currently rejects submissions. Browser/device handoff must survive app pause and cancellation. [OAuth][oauth] |
| A11 | Profile / credentials and disconnect | PUT `env` body `{key,value,profile}`; DELETE `env` body `{key,profile}`. Credential lifecycle reconciles stale config copies. DELETE `providers/oauth/{id}?profile=...` supports eligible providers. Root/external fallback complicates what disconnect means; reread effective readiness. No arbitrary-profile pool-account removal contract established. [Env][env], [OAuth][oauth], [auth storage][auth] |
| A13 | Profile / auxiliary models | GET `model/auxiliary`, POST `model/set` with `scope: auxiliary`, task, provider, model, profile. Empty task applies all slots; `__reset__` resets all. Label these distinctly. Show stale assignments against available providers. [Models][models], [auxiliary persistence][aux] |
| A14 | Profile / execution defaults | Use scoped config for `fallback_providers`, selected `agent.*` limits and `delegation.*` limits/fallbacks. Offer a small curated editor, not every schema field. New default does not prove an active agent has reloaded it. [Config][config], [live schema][live] |
| A17 | Server / profile collection | GET/POST `profiles`, PATCH/DELETE `profiles/{name}`. Explicit `clone_from`, `clone_all` and `clone_channels` control copying. Rename/delete can stop a gateway. Default profile renaming changes display name while canonical ID stays `default`. Read back returned identity and refresh the collection. [Lifecycle][profiles] |
| A18 | Profile / skill usage | Use `skills[].usage` and server metadata. Do not fabricate popularity or interpret missing usage as failure. Search and sorting can remain local to the loaded list. [Skills][skills] |
| A19 | Profile / learned/local skill correction | Learning node detail/edit/archive and skill-content APIs exist. Distinguish archive from memory deletion. Respect provenance, pinning and backend rejection; do not offer edits to every bundled skill. [Learning mutations][learning-mutations], [skills][skills] |
| A20 | Profile / skill Hub | Catalog/search/preview/scan are explicit discovery actions. Install/uninstall/update launch profile-scoped CLI actions and return name/PID. Update endpoint updates the profile's installed Hub skills as a group. Wait for actual action result and refresh installed inventory. [Skills][skills], [action launcher][action-launch], [action status][actions] |
| A22 | Profile / tool setup | GET `tools/toolsets/{name}/config` gives providers, key metadata and prerequisites; models, provider, env and post-setup have dedicated routes. Profile configuration can launch installation of host dependencies. Show that effect before setup. Tool inventory readiness has the source-level scope concern below. [Tools][tools] |
| A24 | Profile / MCP inventory and access | Scoped REST inventory plus RPC `mcp.servers.status` and `mcp.servers.test`. Status is cached and does not establish a connection. Test returns tool metadata and prompt/resource counts. Do not promise full prompt/resource browsing from those counts. Per-tool filters live in `mcp_servers.<name>.tools.include/exclude`. [MCP REST][mcp], [MCP RPC][mcp-rpc], [Desktop MCP][desktop-mcp] |
| A25 | Profile config; Server runtime reload | Scoped enable/delete and test/OAuth RPC exist. Test actually connects or starts stdio. OAuth supports client callback relay but needs a working Android return path. `reload.mcp` is not profile-scoped and changes the running registry; it must be a clearly identified runtime action, not a selected-profile connector save. [MCP][mcp], [MCP RPC][mcp-rpc], [reload][reload] |
| A27, mixed | Profile / agent plugins | Proposed P1: inventory/status and individual enable/disable via scoped `plugins.manage`. Scoped install and catalog update also exist if selected for the build. No remove action exists in that scoped dispatcher. Legacy dashboard REST removal targets the launch home. Desktop UI halves do not supply Android UI. Generic installation/removal/advanced updates remain P2 in the proposed split. [Plugin RPC][plugin-rpc], [legacy REST][dashboard-plugins] |
| A28 | Profile / memory settings | Scoped config supports memory/user-profile enablement and character budgets. Budgets are characters, not tokens. Legacy GET `memory` provides launch-home retained-file status only; do not reuse it for another selected profile. Graph content does not establish exact file-byte status. [Config][config], [live schema][live], [memory ops][memory-ops] |
| A31, mixed | Profile / compression | Proposed P1: enable, threshold, target ratio and protected recent messages using scoped config. Engine/provider selection and advanced tuning remain P2. Generic config exposes `context.engine`, while the legacy plugin-provider setter is launch-home-only. [Config][config], [live schema][live], [legacy plugins][dashboard-plugins] |
| A32 | Profile / approval policy | Scoped config supports `approvals.mode`, timeout, `command_allowlist`, `approvals.mcp_reload_confirm`. This is backend policy, distinct from per-chat YOLO. Saving arbitrary-profile policy does not reconfigure the current runtime's reload confirmation. [Config][config], [reload][reload] |
| A33, mixed | Profile / reach and recovery policy | Proposed P1: secret redaction, private-URL access and checkpoint enablement. Real-browser profile permissions and advanced checkpoint tuning remain P2. These are backend settings, not Android app permissions. [Live schema][live], [config][config] |
| A38 | Health / runtime logs | GET `logs` supports file, lines, level, component and search, but no profile selector. Label as dashboard/runtime-profile logs. Use bounded pages and explicit refresh. Do not assume arbitrary log text is fully redacted or export it automatically. [Logs][logs] |
| A39 | Health / diagnostic actions | POST `ops/doctor` and `ops/security-audit`, then GET `actions/{name}/status`. Launch-profile/runtime actions, not arbitrary-profile diagnostics. Doctor is invoked without `--fix`. Show pending/running/completed/failed and output. No repair was run in this audit. [Ops][ops], [doctor][doctor], [actions][actions] |
| A42 | Health / selected-profile usage | GET `analytics/usage` and `analytics/models`, profile + days from 1 to 365. Show provider/model breakdown and server estimates. Days are rolling cutoffs; label a one-day view "Last 24 hours" unless calendar aggregation is implemented. Handle corrupt DB 503 distinctly. [Analytics][analytics] |
| A44, mixed | Profile / backend voice | Proposed P1: supported provider/model/voice/language and automatic-speech defaults using tool setup plus scoped config. Advanced engine tuning, local model installation and desktop recording keys stay outside P1. Android microphone/playback preferences remain device-owned. [Tools][tools], [live schema][live] |
| A45, mixed | Local navigation / scoped settings search | Proposed P1: search the curated settings index and navigate to the owning editor, with server/profile context in results. Scoped import/export/reset remains P2. Sparse config merge is not a reset API. [Config][config], [profile archive routes][profiles] |

Existing A16 description/SOUL remains under Profile. Existing A36 connection editing belongs with the selected server. Existing A37 diagnostics/usage moves under Health; A41 keeps its existing version/update flow. This audit authorizes no update. All P2-only, separate-candidate and excluded rows in the roadmap remain outside the proposed P0/P1 build.

## Contracts that affect correctness

### Memory IDs need conflict handling

Memory IDs include source and positional index. The mutation resolves the current file chunks from that index and then rewrites the file. Atomic file replacement prevents a partial file, but there is no expected revision/content check. Another client or agent inserting/removing a chunk can make an old ID point at different content within the same source. [Mutation implementation][learning-mutations]

A client reread before Save can catch an already-observed change, but cannot close the race between that reread and the mutation. To claim safe concurrent correction, the backend needs stable identity plus expected-version semantics, or a mutation accepting expected content/version and rejecting a mismatch. That backend change is not authorized by this research. Do not hide this limitation behind optimistic readback. The read-only A07 UI is independent of this gap.

### Readiness has both ownership and source

Profile env APIs read/write that profile's dotenv. Auth state prefers a profile store but can fall back to the root store; external CLI credentials and shared provider grants also exist. "Available to this profile" does not imply "stored only in this profile." Avoid representing every account as an isolated profile-owned secret or promising that removal revokes every fallback. Use source metadata when exposed and reread status after changes. [Env][env], [auth fallback][auth]

The toolset-list route exits its profile scope before computing `configured`. The helper can consult environment/provider readiness using current home. This is a source-level risk for non-current profiles, not a live reproduced mismatch. The detailed tool-config route retains its scope around readiness resolution, so it is a better source for a recovery form. Backend fixtures with deliberately different credentials are needed before claiming inventory readiness isolation. [Tool inventory][tools], [readiness helper][tool-keys]

The credential-pool REST API has no profile argument. It also loads pools through logic that may seed credentials or contact providers. It was not passively probed. Full multi-account administration for arbitrary profiles remains a contract gap. [Credential pool][pool]

### Save semantics differ

PUT `config` merges a sparse patch into raw existing config under a mutation lock. Omitted keys survive. Use it for targeted forms without resending unrelated secrets or stale values. The Desktop model component has a comment saying "replaces"; the backend implementation is the authority. The schema offers many string fields without full validation ranges, so it is a discovery aid, not a ready-made mobile form specification. [Config writer][config], [Desktop controls][desktop-models]

PUT `mcp/servers` replaces the complete MCP map. A per-tool toggle implemented through this map can overwrite another client's concurrent connector changes. Reread and preserve unrelated entries, and record that no compare-and-swap was established. A future targeted/versioned backend write is preferable where concurrent changes must be guaranteed safe. [MCP writer][mcp]

Auxiliary reset-all clears endpoint credentials as well as model/provider assignments while preserving other slot settings. For a single automatic slot, use a named task and the supported assignment contract; do not use the all-slot reset token. [Auxiliary persistence][aux]

A successful response means a setting persisted, not that every existing chat or gateway adopted it. Main model changes explicitly apply to new sessions. Describe other settings as saved defaults until their specific runtime adoption has been verified. [Model assignment][models]

### Background actions need identity and readback

Skill Hub and tool setup return action acknowledgements. Status exposes name, PID, running, exit code and log lines. Some names are shared across profiles, such as skills update and tool post-setup. A later action can replace the status entry. Track connection + action name + returned PID, refuse to attribute a mismatched PID's result, and refresh the owning resource. Client-side serialization cannot prevent another client from starting a same-name action. [Launcher][action-launch], [status][actions]

Profile creation can partially succeed: the profile is created before optional model/MCP/Hub steps, which are best-effort and returned separately. Show partial success with recovery links. Rename/delete may stop gateways, so the UI must describe the actual effect and refresh affected workspaces. A renamed default profile remains canonically `default`. [Lifecycle][profiles]

### MCP configuration is distinct from live runtime state

Cached MCP status can omit live runtime facts for a foreign profile. Do not label that as "disconnected" solely because no runtime connection is reported. Testing creates a real connection and is a user action. Prompt/resource counts are not inventories. Runtime reload is global to the process and requires the backend's confirmation handshake where requested. [MCP RPC][mcp-rpc], [reload][reload]

## UI structure and build order

Use short tab roots with drill-down rows. A reasonable Profile root has Defaults, Identity, Memory, Skills and tools, Accounts and connectors, and Behavior. Each row carries a useful one-line summary; detailed inventory and editors live one level deeper. Keep the chosen profile visible in those editors.

Server can stay short: Connection, Profiles, and Runtime/version information. Do not fill it with profile controls to make the tabs equal length. Health can show runtime health and scoped usage, with errors linking to the setting's owning editor.

1. Add the C shell and captured administration scopes. Rehome existing model, SOUL/profile, Skills/Tools, diagnostics and usage flows. Include loading, offline, unavailable and failed states from the start.
2. Finish independent P0 work: reasoning/speed capability handling, memory reading and source-aware provider readiness. Build memory mutation fixtures and settle the conflict contract before claiming A08 complete.
3. Deliver narrow recovery flows: key rotation, supported device-code login, tool-specific setup and action tracking. Then auxiliary assignments and skill correction/Hub actions.
4. Add profile lifecycle and clearly scoped operational diagnostics. Add MCP configuration/status and supported plugin controls with contract gaps visible in the implementation checklist.
5. Add the remaining curated P1 settings and search. Apply the mixed-row split above explicitly rather than importing entire Desktop settings pages.

Acceptance should cover two distinct profiles on each of two server fixtures, selection changes during reads and saves, rejected/partial writes, disappeared or renamed profiles, unsupported APIs, action PID replacement, expired/cancelled OAuth, empty and populated memory, concurrent memory edits, and server readback. Existing host tests for the first slice remain useful but do not prove these new flows.

No additional visual direction is required to start the shell. The material unresolved issues are backend contracts and populated test fixtures, not the tab layout.

## Primary sources

References below point to the inspected local files. Line numbers are anchored to the source revision recorded above; they can shift after an update.

[scopes]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_server_profiles.py:153>
[config]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/config_env.py:78>
[env]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/config_env.py:224>
[models]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/models.py:52>
[aux]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_server_config.py:681>
[desktop-models]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/apps/desktop/src/app/settings/model-settings.tsx:534>
[skills]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/skills.py:97>
[tools]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/tools.py:216>
[tool-keys]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/tools_config.py:728>
[learning-routes]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/status.py:583>
[learning-mutations]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/agent/learning_mutations.py:34>
[oauth]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/oauth.py:572>
[auth]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/auth.py:472>
[pool]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/ops.py:300>
[profiles]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/profiles.py:652>
[mcp]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/mcp.py:76>
[rpc]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/tui_gateway/methods_tools.py:19>
[mcp-rpc]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/tui_gateway/methods_tools.py:1163>
[reload]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/tui_gateway/methods_tools.py:262>
[desktop-mcp]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/apps/desktop/src/app/skills/mcp-tab.tsx:817>
[plugin-rpc]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/tui_gateway/methods_tools.py:1333>
[dashboard-plugins]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/dashboard_ui.py:139>
[memory-ops]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/ops.py:446>
[ops]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/ops.py:503>
[doctor]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/doctor.py:165>
[logs]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/status.py:720>
[analytics]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/analytics.py:143>
[action-launch]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/_common.py:73>
[actions]: <C:/Users/rober/AppData/Local/hermes/hermes-agent/hermes_cli/web_routers/actions.py:328>
[android-transport]: <C:/Users/rober/OneDrive/Documents/Cursor Projects/hermes-android/lib/core/services/connection_manager.dart:74>
[scope-adr]: <C:/Users/rober/OneDrive/Documents/Cursor Projects/hermes-android/docs/adr/0001-request-scoped-hermes-profiles.md>
[live]: ADMINISTRATION_LIVE_READS_2026-09-14.json
