# Mobile administration roadmap

Selected on 2026-09-14. This expands the earlier small administration placeholder.
It does not authorize Hermes source/deployment changes or restore Firebase work.
All writes use existing authenticated APIs. Backend settings belong to the named
server/profile and affect its clients; selecting a profile remains client-local.

The complete Desktop feature inventory remains in
[management research](research/HERMES_DESKTOP_MANAGEMENT_INVENTORY_2026-09-11.md).
The checklist below assigns implementation priority to those administration
features. Existing connection, conversation and device-preference features are
listed for context, not proposed again as new work.

Implementation update, 2026-09-14: the expanded Studio Profile / Server / Health
screens are now in Flutter source. See the
[implementation and validation record](ADMINISTRATION_IMPLEMENTATION_2026-09-14.md)
for current per-feature coverage, tested states and explicit backend gaps. The
historical first-slice notes below do not supersede that record. Android release
acceptance and the listed unsupported backend operations are not claimed complete.

## Selected administration design

On 2026-09-14 the user selected prototype C, with **Profile**, **Server** and
**Health** tabs. Preserve this ownership split when building. This records a
design decision; it does not claim the expanded administration is implemented.

- **Profile:** configuration owned by the selected profile. Defaults, SOUL,
  memories and profile capability settings belong here when the backend confirms
  that scope.
- **Server:** configuration owned by the selected server, including shared
  installations and credentials where those are server-owned. Managing the
  server's profile collection belongs here; editing an individual profile's
  configuration belongs under Profile.
- **Health:** diagnostics, logs, readiness and usage. Show the scope of each
  result explicitly. Profile-specific usage needs an explicit profile selection;
  a Health tab does not turn scoped measurements into server-wide measurements.
  Recovery links lead to the editor in its owning tab.

Classify individual operations, not whole feature names. A shared installation
and a profile-specific enablement setting can belong to different tabs. Verify
actual backend read/write behavior before placing provider accounts, MCP,
plugins, memory controls, voice and other potentially mixed-scope settings.
The prototype's sample scope labels are not backend evidence.

Provider-account clarification after the owner's single-login observation:
the [source recheck](research/PROVIDER_CREDENTIAL_SOURCE_RECHECK_2026-09-14.md)
confirms that named profiles inherit shared root credentials unless overridden.
Shared provider accounts belong under Server / Providers. Profile retains model
choices, effective-access information and explicit credential overrides. MCP
remains profile-owned. A profile parameter proves a targeting option, not that
the effective account is owned by that profile. See the corrected
[design map](design/2026-09-14-administration-handoff.md).

The selected server remains visible across all tabs. Show the profile selector
for profile configuration and explicitly scoped health views. Changing a profile
must not change the target of server-owned writes. Capture the owning server and,
where applicable, canonical profile identity when opening an editor; switching
selection or receiving a late response must not redirect a save or overwrite the
new selection's state. Server and Health remain usable without a loaded profile
where their underlying operations permit it.

Build approach:

1. Map each P0/P1 operation to its supported endpoint, actual ownership, affected
   clients and completion/readback behavior. Split mixed P1/P2 rows into concrete
   subfeatures before treating their P2 portions as implementation scope.
2. Build the three-tab shell using existing Android styling. Rehome the existing
   model, profile, capability, diagnostics and usage flows before adding features.
   Reuse authenticated transport with explicit server/profile administration
   interfaces; do not force server operations through a selected-profile context.
3. Finish missing P0 work, then deliver P1 in working slices: memory and skill
   correction, capability recovery, profile lifecycle and operational controls,
   followed by the remaining selected P1 features.
4. Verify scope isolation across two profiles and two servers, selection changes
   during reads/saves, unsupported controls, rejected writes and actual background
   action results. Validate working slices against disposable backend fixtures
   and on a phone or emulator.

Keep tab roots short. Use categorized rows and drill-downs, with short editors
in sheets and longer inventories/editors on dedicated screens. Search results
must identify scope and navigate to the owning editor. Do not duplicate a setting
under multiple tabs merely to make it easier to find.

## Priority and feature checklist

The [2026-09-14 local-server scope audit](research/ADMINISTRATION_SCOPE_AUDIT_2026-09-14.md)
maps every P0/P1 row to its backend contract, records 39 sanitized live GET
observations across three profiles and proposes explicit splits for mixed P1/P2
rows. It is research evidence, not implementation acceptance.

The corrected credential-source recheck places shared provider accounts under
Server and explicit profile overrides under Profile. MCP configuration and most
agent-plugin operations belong under Profile. Legacy endpoints without a profile
selector often use the dashboard's launch profile; they are not necessarily
server-wide. Server contains shared providers, connection/runtime administration
and the profile collection. Health labels runtime and selected-profile results separately.

Before claiming the corresponding features complete, resolve memory edit
conflicts caused by positional IDs, verify toolset readiness across different
credential scopes, and account for APIs missing arbitrary-profile support.
The audit also documents whole-map MCP writes and shared background-action names.
These gaps do not block the three-tab shell or independent supported features.

P0 supports frequent phone work or unblocks a task. P1 is useful recovery or
occasional administration. P2 is advanced, account-dependent or less frequent.
Separate candidates remain outside the previously selected scope. Desktop-only
features are listed to make the exclusions explicit.

| ID | Feature | Priority | Mobile value and current boundary |
| --- | --- | --- | --- |
| A01 | Read/change profile default provider and model | P0 | Pick a faster, cheaper or more capable default for new sessions. Implemented in source; release acceptance pending. Per-chat selection already exists and stays separate. |
| A02 | Default reasoning effort and supported service/speed tier | P0 | Choose a practical default for routine work. Show only server/model-supported choices. Not included in the first model-only slice. |
| A03 | Browse/search installed skills, metadata, provenance and complete instructions | P0 | Know which capability to ask Hermes to use. Implemented in source; release acceptance pending. |
| A04 | Enable/disable an individual skill | P0 | Restore useful capabilities or remove irrelevant ones. Implemented in source; release acceptance pending. |
| A05 | Toolset inventory, enabled state, configured state, tool list and platform | P0 | Explain why a task cannot use a capability. Implemented in source; release acceptance pending. Enabled does not mean configured. |
| A06 | Enable/disable individual toolsets | P0 | Recover or limit capabilities without returning to Desktop. Implemented in source; release acceptance pending; enabling unconfigured tools may invoke existing backend setup. |
| A07 | List/search/read retained memories | P0 | See what Hermes remembers before correcting it. Use a list rather than Starmap's canvas. Next administration slice. |
| A08 | Edit/delete individual memories | P0 | Correct persistent mistakes. Confirm removal and read back edits. Next administration slice. |
| A09 | Provider/account inventory and readiness | P0 | Explain missing models or authentication failures. Basic readiness already exists; per-account detail is new. |
| A10 | Reconnect provider accounts through supported key/browser/device-code flows | P1 | Recover expired access from the phone. External backend CLI login remains an external prerequisite. |
| A11 | Rotate provider/service credentials; disconnect accounts | P1 | Unblock a task or revoke access. Dedicated secret input, no secrets in chat/logs. |
| A12 | Custom OpenAI-compatible endpoints/provider definitions | P2 | Useful for self-hosting, but infrequent and error-prone on a small screen. |
| A13 | Auxiliary-model assignments, reset-to-default and stale-provider warnings | P1 | Repair vision/other helper tasks and avoid unwanted provider usage. |
| A14 | Fallback models, agent/subagent limits and execution defaults | P1 | Balance cost and task reliability. Use supported schema fields; show scope clearly. |
| A15 | Mixture-of-agents slots/presets/aggregator | P2 | Advanced configuration with many interdependent choices. |
| A16 | Profile description and SOUL editing | Existing | Already saves and reads back selected-profile values. |
| A17 | Create/clone/rename/delete profiles | P1 | Manage useful specialists from the phone. Canonical identity, deliberate deletion and existing server APIs are required. |
| A18 | Skill usage counts/server-provided ordering | P1 | Help find useful skills. No locally invented popularity ranking. |
| A19 | Edit/archive learned or local skills | P1 | Correct persistent instructions. Respect provenance; bundled skills are not freely editable. |
| A20 | Skill catalog/Hub preview, install, uninstall and update | P1 | Add a capability needed for a task. Show provenance and actual background action results. |
| A21 | Bulk skill/tool toggles and disable-unused actions | P2 | Less frequent than individual corrections; serialize backend read-modify-write operations. |
| A22 | Toolset setup: providers, keys, models, prerequisites and post-setup status | P1 | Make an unavailable tool actionable. Begin with status/readiness, then narrow setup forms. |
| A23 | Backend browser/computer-use/terminal configuration | P2 | Useful for recovery; desktop runtime installation and browser-profile copying are not Android features. |
| A24 | MCP inventory/status, tools/prompts/resources and per-tool toggles | P1 | Understand and control access to connected systems. |
| A25 | MCP probe/reload, OAuth, enable/disable and remove | P1 | Repair broken connectors from the phone. |
| A26 | MCP catalog install, import and raw configuration | P2 | Occasional setup; raw JSON is secondary to guided choices. |
| A27 | Backend plugin inventory/status, enable/disable/install/remove/update | P1/P2 | Useful for capabilities. Desktop UI plugins cannot automatically supply Android screens. |
| A28 | Memory enablement, budgets and retained-file status | P1 | Control retained information with small, explicit settings. |
| A29 | Memory provider selection/configuration/OAuth/reset | P2 | Scope varies by operation. Legacy memory status/reset targets the launch home, while some provider-config routes accept a profile. See the scope audit; do not label launch-home writes as selected-profile writes. |
| A30 | Curator status/pause/resume/run-now | P2 | Occasional learning maintenance; explain effects before running it. |
| A31 | Context engine and compression thresholds/targets/protected recent messages | P1/P2 | Relevant to long chats, but default settings should suffice for most use. |
| A32 | Approval mode/timeout, command allowlist and MCP reload confirmation | P1 | Adjust backend safety policy deliberately. Existing per-chat YOLO is separate. |
| A33 | Redaction, private-URL access, file checkpoints and browser-profile permissions | P1/P2 | Control the backend's reach and recovery behavior. These are not Android permissions. |
| A34 | Vault sources, readiness and lock/unlock | P2 | Can unblock authorized tasks, but requires configured backend vault providers. |
| A35 | Vault login/payment/address records and OTP metadata | P2 | Requires dedicated handling for sensitive data; not a generic settings form. |
| A36 | Connection registry, URL/password/custom headers/test/recovery | Existing | Already implemented. SSH configuration import, OAuth and Cloud onboarding remain separate candidates. |
| A37 | Authenticated diagnostics, provider readiness and scoped usage | Existing | Already implemented and tested against actual Hermes. |
| A38 | Log categories, severity/search and recent errors | P1 | Understand failures remotely without exposing an endless console. |
| A39 | Doctor/security audit and action status | P1 | Diagnose problems while away. Use existing APIs and display results; no automatic repairs. |
| A40 | Backup and explicit diagnostic export/share | P2 | Useful owner tools with clear destination/content review. No automatic external sharing. |
| A41 | App/backend versions and eligible backend updates | Existing | Existing client flow. No update is part of this implementation/testing work. Remote TUI restart remains unsupported. |
| A42 | Usage time ranges and per-model detail | P1 | Extend existing usage view. Server estimates are not external-provider bills. |
| A43 | Cloud balance/plan/credits/top-up/payment portals/auto-reload | P2, conditional | Only for an account/backend exposing billing. Invoice browsing is not present in the audited Desktop. |
| A44 | Voice STT/TTS provider/model/voice/language and automatic speech | P1/P2 | Voice is useful on mobile; provider configuration follows basic capability management. |
| A45 | Settings search, scoped import/export/reset | P1/P2 | Search becomes useful as administration grows; reset/import needs explicit scope and review. |
| A46 | Messaging channel health, pairing approve/revoke | Separate candidate | Valuable mobile supervision, but previous messaging exclusions are not silently reversed by this first admin slice. |
| A47 | Channel enablement/credentials/configuration/restart and Telegram onboarding | Separate candidate | A distinct integration setup flow; no Firebase implication. |
| A48 | Cron list/search/history/pause/resume/run-now/delete | Separate candidate | Strong phone value if scheduling is selected; retained outside the current first slices. |
| A49 | Cron authoring/editing/blueprints/delivery/model overrides | Separate candidate | Requires a coherent scheduling workflow, including script-only jobs. |
| A50 | Webhook service/subscriptions/configuration/one-time secrets/delivery | Separate candidate | Occasional integration setup often involves another system. |
| A51 | Bots, canonical chats, groups and memberships | Separate candidate | Not automatically equivalent to ordinary profile management. |
| A52 | Plugin-gated Kanban boards/tasks/runs/orchestration | Separate candidate | Useful only if the product adopts that workflow and backend plugin. |
| A53 | Local backend process installation, local model downloads/runtime lifecycle, SSH-config discovery | Low / excluded | Android connects to an existing backend; do not recreate a desktop machine manager. |
| A54 | Desktop windows/tabs/glass/keyboard bindings, desktop plugin routes/hot reload, uninstall cleanup | Low / excluded | Device-specific Desktop controls. Android's own appearance and text settings already exist. |
| A55 | Animated Starmap/timeline/share codes, pets and Radio | Low / excluded | Memory inspection is useful; the visual/decorative desktop experiences are not priorities. |
| A56 | Completion/input notifications and device controls | Existing with coverage limits | See notification findings below. Firebase push was dropped and is not an unfinished admin milestone. |

## Delivery slices

1. **Profile defaults and capabilities:** A01, A03–A06. One model editor and one
   Skills/Tools screen under existing administration. Search, inspect and make
   individual changes. No bulk operations, credential editor or installer UI.
2. **Memory correction:** A07–A08, then A19 where the same learning-node APIs
   support it. Preserve distinct delete-memory/archive-skill language.
3. **Recover broken capabilities:** A09–A11 and A22, starting with truthful
   readiness/status and the simplest supported setup paths.
4. **Profile and operational control:** A17, A32, A38–A39. Expand only after the
   preceding slices work against real Hermes.

Other selected priorities remain listed for subsequent work; separate candidates
and excluded desktop features are not implementation commitments.

## First-slice API evidence

Full official source inspected under the existing local Hermes checkout:

- Desktop `src/api/models.ts`: GET `model/info`, GET `model/options` with
  `explicit_only=1`, POST `model/set` with `scope: main`, provider and model.
  `src/store/cron-model-impact.ts` preserves the `confirm_required` handshake.
  Backend main-model assignments apply to new sessions; running chat model
  changes use the separate session API.
- Desktop `src/api/skills.ts`, backend `hermes_cli/web_routers/skills.py`:
  GET `skills`, GET `skills/content?name=...`, PUT `skills/toggle` with name
  and enabled. All use the selected profile query.
- Desktop `src/api/toolsets.ts`, backend `web_routers/tools.py`: GET
  `tools/toolsets`, PUT `tools/toolsets/{name}` with enabled. Preserve separate
  `enabled`, `configured`, platform and tool inventory. Existing backend
  enablement may start post-setup work; show this honestly.
- Existing Android `ProfileGateway` pins the connection and profile. Reuse
  `DashboardClient` authentication and PUT transport; do not add another client.

## Notification findings

Historical diagnosis from 2.32.0. The connected-app reconciliation described below shipped in 2.34.2; see [local alert QA](LOCAL_ALERT_QA_2026-09-14.md) for passing checks and remaining delivery limits.

On the installed 2.32.0 client, a read-only phone check confirmed notification
permission granted and the Hermes channel enabled at default importance. The
reported symptom is occasional alerts, with most expected alerts missing.

The current live-event path only resolves chats already opened/created/resumed
by that app process. `ProfileWorkspaceController._event` ignores events whose
runtime ID does not match a loaded `ProfileChat`; registry controllers and
profile resources are created lazily. Merely having a chat row in the list does
not monitor it. Reconnect can notify for known running chats that settle while
disconnected, but does not establish general monitoring of unopened work.

These source findings are consistent with sparse alerts, but are not a captured
trace of a particular missed notification. No transport fix is claimed. A
passing test notification proves OS posting only. A real local Hermes turn passed
through the production controller and delivered one completion callback for the
correct QA profile/chat with `visible=false` (2026-09-14,
`test/profile_notification_live_test.dart`, six seconds). This is host-side
event-path evidence, not an Android background lifecycle or native posting test.
The next check must correlate a real completion with native posting while Android
is backgrounded. Do not restore Firebase or invent
session ownership from an unknown runtime event. General monitoring needs an
existing authoritative event/discovery contract and a separate battery/lifecycle
decision; it is not addressed by adding notification switches.

The gateway source confirms the boundary: `tui_gateway/server.py:573-597`
routes session events through that session's attached transport. Normal completion
(`prompt_turn.py:837-849`), approval and clarification use that path. Resume and
activate attach the requesting client (`methods_session.py:664-686,928-940`).
The global `sessions.changed` broadcast is instead an empty, coalesced invalidation
(`change_watcher.py:173-219`), advertised by `gateway.ready.change_events`.
It contains no profile, session, status or pending-request payload.

Next client fix: use that invalidation to reconcile server session status for
connected targets, detect relevant transitions, and open/resume only when request
detail is needed. Keep snapshots transient and avoid attaching every chat or
inventing event ownership. Prove this with a task started outside the Android
controller before claiming unopened-chat coverage. This improves connected-app
coverage only; Android process suspension/death remains a separate limitation.

## Validation ledger

First slice is implemented in source; release and emulator acceptance are pending.

- Four Skills/Tools widget tests passed: scoped writes/readback, rejected writes,
  late tab responses, setup confirmation, search and instruction reads.
- Existing profile discovery and registry tests also passed: 14 total tests in
  that focused run.
- The actual local Hermes administration test passed through `ProfileGateway`
  against the existing disposable `android-qa-a` profile. It changed a QA skill
  and a configured toolset, checked server readback, restored both and checked
  restoration. It also re-saved the existing configured default model and read
  it back. No model call, provider change or setup install was needed.
- All eight model editor widget tests passed after correcting fixture expectation
  types and animated-dialog waits. Coverage includes captured scope, guarded
  confirmation cancellation/acceptance, mismatched server readback, search and
  Back protection during a save, an initial default for an unconfigured profile, and keyboard layout on a small screen. Static analysis passed for all changed Dart files; the final model edge-case changes also passed targeted analysis.
- No emulator UI result or production deployment is claimed for this slice.
  Another task has started emulator 5556; no second emulator was launched.

## Main integration, 2026-09-14

Reviewed the combined changes from `fa7436d` through `c5eab37`. Main already
contained administration commit `1592bea`, followed by the build-workflow and
composer queue-editing commits. The administration routes and captured gateway
ownership remain compatible with those changes.

The standards review found duplicate model-list parsing. Both pickers now use
`ChatModelChoice.fromOptions`, preserving the original strict response validation.
A regression rejects malformed provider lists rather than offering partial
choices. The spec review found no missing first-slice requirements or scope creep.

The source version is prepared as `2.33.0+2210`, with matching CI checks,
release-identity assertions and a feature-only changelog covering administration
and composer queue editing. This does not claim an APK build or deployment.

- Full static analysis passed.
- Full host test suite passed: 1,460 tests, six opt-in skips, zero failures,
  in 3 minutes 34 seconds using two workers.
- After the final parser validation correction, all 17 affected model-picker
  tests passed, including the new malformed-response regression.
- The integration run used no emulator or APK build. Earlier live-Hermes API
  evidence remains recorded above; the host suite does not replace device QA.
- Before pushing, rebased onto concurrent build-launcher commit `0107b38`.
  It changed no Dart app code. Its PowerShell launcher checks also passed:
  argument/exit-code forwarding, lock preservation, bounded busy-lock failure
  and denied-write handling.
