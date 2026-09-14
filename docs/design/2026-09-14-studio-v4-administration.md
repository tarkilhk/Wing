# Studio administration revision 4

Design-only review, 14 September 2026. The administration research task checked the complete navigation map and resolved the three coordination questions. The brief is sufficient. No Flutter implementation, backend change, update, sign-in, setup or diagnostic action was performed.

Provider placement correction after this board was produced: shared provider accounts belong under Server / Providers. Profile keeps model choices, shared-access information and explicit credential overrides; MCP remains in Profile. See the public source references and [updated map](2026-09-14-administration-handoff.md). The boards remain references for tabs and styling but are superseded for provider-account placement. In particular, inherited-account recovery should open the shared Server account detail, not start a profile-specific sign-in by default.

## Decision status

- Owner-approved: Studio visual direction; Profile / Server / Health ownership split; the earlier conversation-preservation and context-ring decisions.
- Research-aligned proposals: detailed root categories, drill-down placement and five mixed P1/P2 splits. In particular, A27 depicts agent-plugin inventory/status/toggles, not installation/catalog update/removal. This is not fresh owner approval or a change to roadmap priorities.
- Current limitations: safe concurrent memory correction and MCP whole-map filtering still need contract work. Their intended editors are design proposals; the read-only alternatives describe current availability honestly. No backend work is authorized by these boards.

The full P0/P1 map, including required A08 memory correction, is retained in the [resolved administration handoff](2026-09-14-administration-handoff.md). No feature was silently dropped because a write contract remains unresolved.

## Boards

| Board | What to review |
| --- | --- |
| [Light tab roots](images/studio-v4-admin-light.png) | Profile's six categories, Server's three entries, Health's separate scopes; compact summaries and text tabs |
| [Dark tab roots](images/studio-v4-admin-dark.png) | The same navigation in Studio's charcoal/mint palette, with an intentionally short Server page |
| [Recovery and captured context](images/studio-v4-admin-recovery.png) | Missing selected profile while runtime remains available; account recovery; an unconfirmed SOUL save; partial profile setup |
| [Memory correction and MCP access](images/studio-v4-admin-contracts.png) | Intended memory and MCP editors, explicit concurrent-write caveat outside the screens, and current read-only alternatives |

These are generated visual proposals with illustrative data. Exact text, colors, sizes and behavior are governed by the design system and the contracts below. They do not establish rendered Flutter layout, accessibility, endpoint availability or successful writes.

## Root navigation and scope

The common header contains Administration, the selected connection and access to scoped search. Profile / Server / Health use compact text tabs with an accent underline. No pill switcher or new app-wide bottom navigation.

The corrected Profile root contains Defaults, Identity, Memory, Skills and tools, Access and connectors, and Behavior. Its selected-profile control sits below the tabs. Short summaries explain what each category contains without turning every root row into a warning. Inventories, long instructions and detailed readiness remain one level deeper.

The corrected Server root contains Connection, Providers, Profiles and Runtime. Providers owns shared accounts, while profile-specific credential overrides remain under Profile. Server has no selected-profile control or profile-owned memory/policy settings. Runtime links to the existing backend version/update flow and genuinely runtime-wide MCP reload. Those are entries, not automatically executed actions. No restart button or automatic-repair toggle is proposed.

Connection retains the existing saved-connection and device-held credential semantics. Editing the password used to connect is not changing the server's password. Its editor should identify the saved connection and device-local access details rather than imply that every row under Server writes central configuration.

Health separates runtime observations from selected-profile readiness and usage. The profile selector is local to the selected-profile section. Host/process observations do not acquire a profile label merely because logs have one. Runtime logs and Doctor use the dashboard's launch-profile identity; selected-profile usage retains its own identity and rolling time ranges. Recovery opens the single owning editor rather than duplicating settings in Health.

The board intentionally uses a runtime profile named Default and a selected profile named Personal to expose accidental scope conflation. These are sample display labels. Resolve runtime identity from the captured connection's `profiles/active.current`, then profile metadata; do not use `active` or the mobile selection. Canonical identity survives display-name changes. If identity lookup fails, keep the Runtime heading and show "Profile scope unavailable" for results that need it. Supported host/process results can still be shown.

## Recovery and editing

Every editor captures connection and canonical profile when opened. Its scope label is fixed while editing. Root selection changes and late responses cannot retarget saves or replace the newly selected target's data. If the target disappears, retain the draft and explain the unavailable target; do not save to a replacement profile.

Account recovery distinguishes access available to a profile from credentials stored only there. An inherited/shared account opens its Server detail; creating a profile-specific login must be an explicit override choice. Show root/external source only when exposed by the supported contract. Honor the provider's actual login flow rather than forcing the illustrated browser flow for all providers. Pending sign-in survives app pause, supports cancellation and refreshes effective readiness after completion. Do not claim that disconnecting a profile removes every inherited fallback.

The SOUL editor preserves its draft after an unconfirmed save. The compact notice explains uncertainty without an optimistic success state or automatic resend. The bottom action footer remains above the keyboard; close/cancel retains the existing unsaved-change confirmation. Partial field saves identify the successful and unsaved fields separately.

Partial profile creation names the created profile and the setup portion that failed, then links to recovery for that exact profile. Rename/delete disclose actual gateway effects. A default-profile display rename never changes its canonical `default` identity.

## Required future edits and current alternatives

The intended memory flow is list/detail, edit, then Save; deletion uses a distinct confirmation naming the affected memory. The illustrated correction remains required A08 work. Under the current positional-ID contract, show read-only details and unavailable mutation controls rather than presenting a successful or safe edit. Rereading before Save cannot close the concurrent replacement race.

The intended MCP flow is connector tools, staged access changes, review, then Apply. Keep the captured scope and show what changes. Under the current whole-map replacement contract, the read-only alternative exposes inventory and supported Test without claiming safe per-tool writes. A review screen is useful for understanding changes but does not provide conflict protection.

Cached status and explicit Test remain different. "No runtime status available" is not a disconnected state. Test can connect/start the configured server and should say so. Prompt/resource counts are plain values, not browseable inventories. Runtime reload lives under Server; a connector screen may link there with the actual scope, never masquerade as a profile-local reload.

## Additional state contract

| State | Treatment |
| --- | --- |
| Loading / pending | Keep captured target visible; distinguish submitted action from completed result |
| Stale | Retain the dated observation with Refresh; do not render it as current |
| Offline | Keep last-known content marked stale and drafts intact; disable writes needing connection |
| Unavailable capability | Explain at the affected drill-down and preserve safe read-only operations |
| Failed | Name the failed operation and offer the relevant recovery path |
| Uncertain save/action | Keep edits; show outcome unknown; do not silently retry or attribute another action's result |
| Partial success | Separate completed and incomplete parts, with target-specific recovery links |

The boards illustrate selected examples, not every permutation. Action tracking must retain connection and returned operation identity; implementation identifiers do not belong in ordinary screen copy. Logs remain bounded and manually refreshed, with no automatic export. Doctor/security-audit actions do not imply automatic repairs.

## Evidence and next step

This design follows the [roadmap](../ADMINISTRATION_ROADMAP.md) and [ownership handoff](2026-09-14-administration-handoff.md). Read-only research and source inspection do not establish acceptance of future writes. Mutation and runtime-adoption limits remain in force.

The next step is visual review of these proposals by the owner and research task. Remaining detailed states include tool setup with host dependencies, an operation whose result identity changes, profile lifecycle effects, secret input, and narrow/large-text administration layouts. The illustrated memory deletion confirmation is a starting specimen; its final version should include an excerpt of the affected memory. These can refine the selected system without reopening the tab split.

Exact prompts are in [studio-v4-prompts.md](2026-09-14-studio-v4-prompts.md), with the [recovery header correction](2026-09-14-studio-v4-recovery-correction.md) recorded separately. The built-in image-generation tool used the previous administration board as a style reference. That previous board is superseded for navigation; the conversation design is unchanged.

Visual inspection notes: the light and dark boards preserve the same ownership map, but generated icon shapes and selector chevrons vary slightly. Use one consistent icon set and a downward selector chevron in the final specification. Health's common header must show only the connection. The recovery image was corrected where it originally inherited a combined connection/profile header. All enabled-state samples and inherited-account facts are illustrative, not new live observations.
