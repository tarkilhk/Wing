# Administration roadmap

The owner selected this scope on 14 September 2026. [Administration](ADMINISTRATION.md) documents the current controls and unsupported operations. This priority register preserves the original feature IDs; it is not a claim that every listed operation has shipped.

P0 covers frequent phone work or unblocking a task. P1 covers recovery and occasional administration. P2 covers advanced or account-dependent work. Separate candidates and excluded features are not implementation commitments. Use existing Hermes APIs and the [ownership handoff](design/2026-09-14-administration-handoff.md).

## Scope register

| ID | Feature | Priority |
| --- | --- | --- |
| A01 | Read/change profile default provider and model | P0 |
| A02 | Default reasoning effort and supported service/speed tier | P0 |
| A03 | Browse/search installed skills, metadata, provenance and complete instructions | P0 |
| A04 | Enable/disable an individual skill | P0 |
| A05 | Toolset inventory, enabled state, configured state, tool list and platform | P0 |
| A06 | Enable/disable individual toolsets | P0 |
| A07 | List/search/read retained memories | P0 |
| A08 | Edit/delete individual memories | P0 |
| A09 | Provider/account inventory and readiness | P0 |
| A10 | Reconnect provider accounts through supported key/browser/device-code flows | P1 |
| A11 | Rotate provider/service credentials; disconnect accounts | P1 |
| A12 | Custom OpenAI-compatible endpoints/provider definitions | P2 |
| A13 | Auxiliary-model assignments, reset-to-default and stale-provider warnings | P1 |
| A14 | Fallback models, agent/subagent limits and execution defaults | P1 |
| A15 | Mixture-of-agents slots/presets/aggregator | P2 |
| A16 | Profile description and SOUL editing | Existing |
| A17 | Create/clone/rename/delete profiles | P1 |
| A18 | Skill usage counts/server-provided ordering | P1 |
| A19 | Edit/archive learned or local skills | P1 |
| A20 | Skill catalog/Hub preview, install, uninstall and update | P1 |
| A21 | Bulk skill/tool toggles and disable-unused actions | P2 |
| A22 | Toolset setup: providers, keys, models, prerequisites and post-setup status | P1 |
| A23 | Backend browser/computer-use/terminal configuration | P2 |
| A24 | MCP inventory/status, tools/prompts/resources and per-tool toggles | P1 |
| A25 | MCP probe/reload, OAuth, enable/disable and remove | P1 |
| A26 | MCP catalog install, import and raw configuration | P2 |
| A27 | Backend plugin inventory/status, enable/disable/install/remove/update | P1/P2 |
| A28 | Memory enablement, budgets and retained-file status | P1 |
| A29 | Memory provider selection/configuration/OAuth/reset | P2 |
| A30 | Curator status/pause/resume/run-now | P2 |
| A31 | Context engine and compression thresholds/targets/protected recent messages | P1/P2 |
| A32 | Approval mode/timeout, command allowlist and MCP reload confirmation | P1 |
| A33 | Redaction, private-URL access, file checkpoints and browser-profile permissions | P1/P2 |
| A34 | Vault sources, readiness and lock/unlock | P2 |
| A35 | Vault login/payment/address records and OTP metadata | P2 |
| A36 | Connection registry, URL/password/custom headers/test/recovery | Existing |
| A37 | Authenticated diagnostics, provider readiness and scoped usage | Existing |
| A38 | Log categories, severity/search and recent errors | P1 |
| A39 | Doctor/security audit and action status | P1 |
| A40 | Backup and explicit diagnostic export/share | P2 |
| A41 | App/backend versions and eligible backend updates | Existing |
| A42 | Usage time ranges and per-model detail | P1 |
| A43 | Cloud balance/plan/credits/top-up/payment portals/auto-reload | P2, conditional |
| A44 | Voice STT/TTS provider/model/voice/language and automatic speech | P1/P2 |
| A45 | Settings search, scoped import/export/reset | P1/P2 |
| A46 | Messaging channel health, pairing approve/revoke | Separate candidate |
| A47 | Channel enablement/credentials/configuration/restart and Telegram onboarding | Separate candidate |
| A48 | Cron list/search/history/pause/resume/run-now/delete | Separate candidate |
| A49 | Cron authoring/editing/blueprints/delivery/model overrides | Separate candidate |
| A50 | Webhook service/subscriptions/configuration/one-time secrets/delivery | Separate candidate |
| A51 | Bots, canonical chats, groups and memberships | Separate candidate |
| A52 | Plugin-gated Kanban boards/tasks/runs/orchestration | Separate candidate |
| A53 | Local backend process installation, local model downloads/runtime lifecycle, SSH-config discovery | Low / excluded |
| A54 | Desktop windows/tabs/glass/keyboard bindings, desktop plugin routes/hot reload, uninstall cleanup | Low / excluded |
| A55 | Animated Starmap/timeline/share codes, pets and Radio | Low / excluded |
| A56 | Completion/input notifications and device controls | Existing with coverage limits |

## Remaining boundaries

The expanded Profile, Server and Health screens are implemented. Do not restart the historical first model-and-skills slice. Current limitations include positional memory IDs that prevent safe individual edits/deletes, whole-map MCP writes that prevent safe per-tool toggles, incomplete credential provenance and unavailable cold recovery for pending authentication/actions.

Shared provider accounts belong under Server. Profile holds default models, effective account-source information and explicit credential overrides. Removing an override can reveal shared access again. Scope must follow the owning resource rather than the existence of a profile parameter.

For mixed P1/P2 rows, keep implemented narrow settings distinct from advanced configuration. Raw MCP import, mixture-of-agents, memory-provider reset, curator controls, vault record administration, billing, broad import/export and installation flows remain subject to their stated priority and actual backend support.

A46–A52 remain separate candidates. A53–A55 remain excluded from this administration scope. A56 covers local alerts only; see [Notifications](BACKGROUND_NOTIFICATIONS.md).

Use the [testing guide](TESTING.md) for recorded acceptance boundaries. New provider sign-ins, SDK installs and backend self-updates need their own verification; passing settings readback does not establish those operations.
