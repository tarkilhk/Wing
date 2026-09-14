# Administration design handoff

Administration design handoff, 14 September 2026. Read the [administration roadmap](../ADMINISTRATION_ROADMAP.md) for feature scope. This document translates the ownership findings into proposed navigation, not additional implementation approval or independent backend verification. Local research reports and live-read datasets are outside this design publication.

The owner-selected administration structure is Profile / Server / Health. Studio remains the selected visual language. These are separate decisions: administration prototype C defines ownership/navigation; Studio defines appearance. No Flutter or backend work is included.

Provider ownership correction: Hermes resolves [provider state](https://github.com/NousResearch/hermes-agent/blob/e16f686706b1e0d5334fd1ae82190058d2a19694/hermes_cli/auth.py#L773) and [credential pools](https://github.com/NousResearch/hermes-agent/blob/e16f686706b1e0d5334fd1ae82190058d2a19694/hermes_cli/auth.py#L893) through shared root fallback. Shared provider accounts belong in Server / Providers; Profile retains model choices, access-source information and explicit credential overrides. This corrects the earlier blanket Profile placement without moving profile-owned MCP settings. The map below is updated; revision 4 images predate this correction.

## Proposed full P0/P1 navigation map

The Profile root has six grouped drill-down rows. Server has four, including shared Providers. Health has separately scoped sections. Detailed inventories do not occupy the root screens.

| Tab / root row | Drill-down destinations and operations | Roadmap coverage |
| --- | --- | --- |
| Profile / Defaults | Main provider/model, supported reasoning and speed; auxiliary assignments with single-slot versus all-slot reset distinguished; fallback models | A01, A02, A13, fallback portion of A14 |
| Profile / Identity | Description and SOUL. Link to Server / Profiles for collection lifecycle instead of duplicating those operations | Existing A16 |
| Profile / Memory | Search/list/detail; enablement and character budgets. Memory correction remains required P0 but unavailable pending a safe concurrency contract. Retained-file facts shown only where the actual scope supports them | A07, A08, A28 |
| Profile / Skills and tools | Installed skills, instructions/provenance, individual toggles, usage ordering, learned/local correction/archive, Hub preview/install/uninstall/update; toolsets with separate enabled/configured facts and detail/setup; agent-plugin inventory and toggles under a distinct Plugins subpage | A03-A06, A18-A20, A22; proposed P1 part of A27 |
| Profile / Access and connectors | Effective provider access with a link to the shared account's Server detail; explicit profile-specific credential overrides and their supported recovery; MCP inventory, configuration, tool access, explicit Test, supported OAuth, enable/disable/remove | Profile access/override portions of A09-A11, A24, profile-owned portions of A25 |
| Profile / Behavior | Agent/subagent execution limits; approval mode, timeout, allowlist and reload-confirm policy; proposed basic compression, reach/recovery policy and backend voice defaults | Limits portion of A14, A32; proposed P1 portions of A31, A33, A44 |
| Server / Connection | Existing connection URL, password, custom headers, test and repair | Existing A36 |
| Server / Providers | Shared provider accounts and source-aware status; supported shared sign-in/reconnect/key management/disconnect. Capture the verified root owner explicitly; missing profile parameters do not guarantee root targeting | Shared-account portions of A09-A11 |
| Server / Profiles | Inventory, create/clone, rename and delete with explicit object identity, copy choices and gateway effects; entry to an individual profile's configuration navigates to Profile | A17 |
| Server / Runtime | Backend version and existing eligible update flow; explicitly runtime-wide MCP reload, with required confirmation. No remote TUI restart or process installer | Existing backend portion of A41; runtime portion of A25 |
| Health / Runtime | Runtime/launch-profile observations, bounded logs and recent errors, Doctor/security-audit execution and action results. Identify the launch profile where relevant; never describe these as all-profile diagnostics | A38, A39; runtime portion of existing A37 |
| Health / Selected profile | Scoped readiness/diagnostics and usage with rolling ranges and per-model/provider detail. Recovery links to Server / Providers for shared credentials, or the owning Profile editor for overrides/MCP | A42; scoped portion of existing A37, summary links into A09 |
| Administration search | Search a curated local index; results identify server/profile owner and destination. Navigate to the single owning editor; search does not create another settings store | Proposed P1 portion of A45 |

Android app version, microphone/playback preferences, appearance and notifications stay in App settings. Backend voice defaults belong in Profile. Other existing connection/conversation behavior stays intact. No P2-only, separate-candidate or excluded feature becomes part of this map.

## Mixed-priority splits aligned with research

| ID | Proposed P1 included in this navigation | Remains outside this proposal |
| --- | --- | --- |
| A27 | Scoped agent-plugin inventory/status and individual toggles | Install/catalog update pending explicit selection; generic removal and advanced lifecycle P2. No arbitrary-profile Remove from legacy launch-home routes |
| A31 | Compression enablement, threshold, target and protected recent messages | Context engine/provider selection and advanced tuning |
| A33 | Secret redaction, private-URL access and checkpoint enablement | Browser-profile permissions and advanced checkpoint tuning |
| A44 | Supported backend STT/TTS provider/model/voice/language and automatic speech | Advanced tuning, local model installation, Desktop recording keys |
| A45 | Scope-labeled navigation search | Import/export/reset |

The research task confirmed these five splits for the proposed boards. They remain research/design proposals, not fresh owner approval or roadmap priority changes. A27 installation/catalog update stays outside the depicted P1 slice.

## Scope and navigation behavior

Keep the selected connection visible in the common header. Place compact Profile / Server / Health text tabs below it, with an accent underline instead of three large buttons. The Profile selector appears within Profile. In Health it belongs specifically to the selected-profile section; runtime results have their own explicit scope label. Server has no misleading profile selector above its writes.

Keep each editor's captured connection and canonical profile identity fixed, visible and non-switchable while editing. Changing the root selection cannot retarget a pending save; late responses cannot overwrite the new selection. Display names may change without canonical identity changing. A missing profile gives Profile a recoverable unavailable state while supported Server and runtime Health views remain usable.

Use sheets for short choices/secrets, dedicated screens for inventories, provider recovery and long SOUL/skill editors. Retain the proposed keyboard-aware Save footer for long forms. Search results show their actual target before opening it. Health recovery links open the owning editor with that same captured target; Health itself does not duplicate settings forms.

## Contract-driven UI treatment

- Accounts say "Available to this profile" and show inherited/root/external source only when provided. No unsupported profile-specific account pool or promise that Disconnect revokes every fallback.
- Shared accounts are managed once under Server. Profile override removal can reveal shared access again; it is not "disconnect everywhere". Shared-account writes explicitly identify the root store and may affect inheriting profiles. External CLI ownership remains separate, and not every Hermes Codex account is externally managed.
- Toolset enabled and configured remain distinct. Platform is configuration context such as CLI or a messaging channel. Setup explains host-dependency installation before starting; an acknowledgement becomes pending, not completed.
- Memory budgets use characters. A08 remains required P0 work. Depict its intended edit/delete interaction in a clearly annotated future design, alongside the current read-only alternative. Do not imply those writes are safe or available today while positional-ID conflicts remain unresolved. A07 browsing is independent.
- MCP cached status and explicit Test are different. Missing runtime observations mean "No runtime status available", not disconnected. Show tools where returned and prompt/resource counts only. Runtime reload is under Server, with a cross-link from MCP if useful. Whole-map writes remain a concurrency limitation; a review screen alone cannot solve it.
- Skill updates describe their actual group scope. Auxiliary reset-all discloses credential clearing. Save labels distinguish persisted defaults from adoption by an active session.
- Install/setup/diagnostic action progress retains the captured target and returned action identity. A replaced action result becomes unconfirmed rather than attributed to the wrong job. Partial profile creation lists what succeeded and links to recovery for the missing parts.
- Use compact, distinct states for loading/pending, stale data, unavailable capability, offline, failure, uncertain save and partial success. Keep edits visible after unconfirmed saves; stale data carries last-checked information and a refresh action. No technical endpoint/PID clutter in ordinary UI.

## Research coordination resolutions

1. Research confirmed the five proposed mixed-priority splits for depiction, including only inventory/status/toggles from A27. This is proposal alignment, not additional owner approval.
2. Depict the intended MCP per-tool review/apply flow, with an outside-artboard annotation that safe concurrent writes remain pending backend contract work. Include the current unavailable/read-only alternative. A review screen cannot solve whole-map concurrency. Apply the same intended-versus-current distinction to memory A08; do not silently drop the required correction feature. No backend work is authorized.
3. On the captured connection, GET `/api/profiles/active` returns `current`, the launch/runtime profile, and `active`, the sticky future-launch default. Resolve `current` through profile metadata for its display name while retaining canonical identity. Never substitute `active` or the client's selected profile. If resolution fails, show "Runtime" and "Profile scope unavailable" where the observation needs profile identity. Host/process observations remain distinct from launch-profile logs/Doctor. This identity lookup is independent of the selected profile, so its absence need not disable supported runtime Health or Server views. Evidence supplied by research: `hermes_cli/web_routers/profiles.py:712` at the audited revision, and the observed response shape.

No question prevents coherent design. Root rows use short useful summaries; detailed limitations remain in affected drill-downs. No automatic-repairs toggle, new restart control or executed update is included.

## Revised Studio boards

Revision 4 replaces the single scrolling administration overview with separate light and dark boards showing all three tab roots, with an intentionally short Server tab. A recovery board covers missing-profile/runtime-still-available behavior, account recovery, unconfirmed scoped edits and partial profile setup. A fourth board depicts intended memory/MCP editors and current read-only alternatives. Studio typography, restrained rectangles and accent rules are retained; conversation/activity/composer designs are untouched.

The existing `studio-v3-administration.png` remains a style/form reference only. Its information architecture is superseded by the owner-selected tabs and this audited ownership map. The brief was sufficient; all four revision 4 boards are saved and visually inspected. See [revision 4 review](2026-09-14-studio-v4-administration.md) for references, minor raster qualifications and remaining implementation boundaries. No further coordination question blocks design review.
