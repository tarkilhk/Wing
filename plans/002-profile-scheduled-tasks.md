# Plan 002: Manage scheduled tasks under Profile

Status: DONE — implemented and verified on 2026-09-17; unrelated full-suite failures and live acceptance limits are recorded below.

- Planned at Android commit `fd5c1c7`, 2026-09-17.
- Desktop/backend studied: Hermes `af4a3eba0a3674633050bf1c41df45f8ed6f0858` (2026-09-15), available in `/tmp/hermes-vault-source` as a partial checkout.
- Priority P1; effort L; implementation risk medium; no dependency on plan 001.
- Scope of study: desktop cron UI, API/store/actions, scheduler parsing, dashboard routes, Android administration, transport, navigation and Studio. This is not a whole-repository audit or a live-server certification.

## Outcome

Add **Administration → Profile → Scheduled tasks**. A person can understand what will run next, create or change a task, pause/resume it, run it deliberately, and inspect its recent conversations. Hermes executes schedules; Wing manages them. The phone does not need to remain open for server scheduling to operate.

Use the existing selected connection and canonical profile throughout. The destination appears after Skills and tools, with subtitle “Schedules, runs and results”, and participates in administration search. Keep Server and Health ownership unchanged.

## Evidence and current state

Desktop sources at the studied revision:

- [Cron screen](https://github.com/NousResearch/hermes-agent/blob/af4a3eba0a3674633050bf1c41df45f8ed6f0858/apps/desktop/src/app/cron/index.tsx): searchable master/detail view, recurring presets, name/prompt, delivery choices, model override, pause/resume, trigger, delete confirmation, templates and recent runs opening sessions.
- [Cron API](https://github.com/NousResearch/hermes-agent/blob/af4a3eba0a3674633050bf1c41df45f8ed6f0858/apps/desktop/src/api/cron.ts): profile listing, delivery discovery, run history, CRUD, synchronous trigger with a dedicated 24-hour timeout, blueprint discovery/instantiation.
- [Mutation handling](https://github.com/NousResearch/hermes-agent/blob/af4a3eba0a3674633050bf1c41df45f8ed6f0858/apps/desktop/src/app/cron/cron-actions.ts): separate mutation success from refresh failure; refresh after one-shots disappear.
- [Job editor model](https://github.com/NousResearch/hermes-agent/blob/af4a3eba0a3674633050bf1c41df45f8ed6f0858/apps/desktop/src/app/cron/cron-job-model.ts): script-only editing and paired model/provider clearing.
- [Dashboard routes](https://github.com/NousResearch/hermes-agent/blob/af4a3eba0a3674633050bf1c41df45f8ed6f0858/hermes_cli/web_routers/cron.py), [creation helpers](https://github.com/NousResearch/hermes-agent/blob/af4a3eba0a3674633050bf1c41df45f8ed6f0858/hermes_cli/web_server_cron.py), [scheduler](https://github.com/NousResearch/hermes-agent/blob/af4a3eba0a3674633050bf1c41df45f8ed6f0858/cron/jobs.py), [timezone resolution](https://github.com/NousResearch/hermes-agent/blob/af4a3eba0a3674633050bf1c41df45f8ed6f0858/hermes_time.py).

Android seams:

- `lib/core/screens/administration/administration_content.dart`: `_destinations` defines Profile/Server entries; `_searchDestinations` includes them. Add one destination here.
- `lib/core/services/administration_repository.dart`: `ProfileAdministration` captures a canonical name and scope. Reads append `profile`; writes verify that profile still exists and explicitly target it. Its current production transport times out every operation after 45 seconds.
- `lib/core/screens/administration/admin_widgets.dart`: `AdminPage`, `AdminGroup`, `adminPush`, `adminConfirm`, retained observations in `AdminLoad` and shared connection status.
- `lib/core/services/connection_manager.dart`: `DashboardClient._decodeMapResponse` wraps a bare JSON list in `{'data': decoded}`; current mutation helpers discard HTTP error bodies. Unused `createJob`/`updateJob` helpers lack explicit profile scope.
- `lib/core/services/profile_workspace_controller.dart`: `openSession(ProfileSessionKey)` is the existing scoped conversation entry point. Run navigation must use it and the existing app-shell conversation route.
- `test/administration_repository_test.dart`, `test/administration_transport_test.dart`, `test/administration_navigation_test.dart`, `test/support/administration_fixture.dart`: existing testing patterns.

Current shapes to recognize before implementation:

```dart
// ProfileAdministration.read
server.request('GET', endpoint, {...query, 'profile': name}, null);

// Existing update envelope (retain the current server contract)
{'updates': updates}

// The profile editor pattern captures its owner once.
late final _profile = widget.profile;
```

Read `AGENTS.md`, `docs/DESIGN_SYSTEM.md` and `docs/design/2026-09-14-administration-handoff.md`. User instructions require the current target directly: no older endpoint support, implicit profile defaults, schema aliases, migration shims or compatibility adapters. Additional current fields on an existing task must not be erased by editing an unrelated field; use a minimal update, not a replacement record.

## Feature scope

| Capability | Proposed Wing behavior |
| --- | --- |
| Inventory | Selected-profile tasks, search, All / Active / Paused / Needs attention filters, refresh, explicit empty/error/stale states |
| Details | Schedule, server-reported next/last run, status, instructions, delivery, model choice, last error and recent runs |
| Create/edit | Optional name, instructions, schedule, result destinations, profile model or a specific available model |
| Scheduling | Daily, weekdays, weekly, monthly, hourly, every 15 minutes; native time/day controls; custom expression/interval; explicit one-time date/time or delay |
| Operations | Pause, resume, run now, edit, confirmed delete; per-task pending state |
| Results | Latest 20 run sessions, optional “Show more” up to the endpoint's 100-run maximum; open the actual scoped conversation |
| Templates | Secondary “Start from a template” entry in creation; server catalog and typed fields, implemented after the core flow |
| Existing advanced tasks | Show script/skill/configuration facts; allow supported common-field edits without inventing missing prompts or changing execution mode |

No cross-profile overview, Android alarm scheduler, new notification subscription system, script uploading, workflow builder, stop-running endpoint, or unlimited history is included. Completed script-only jobs may have no conversation: say so, without fabricating output or a session.

## Studio design specification

The design signature is **a readable next-run line**: task name first, then a prominent time and quieter cadence. It answers “what happens next?” without dashboard counters or decorative cards. Detail repeats the same rhythm at a slightly larger scale. These are ordinary Studio grouped rows, not an extra timeline component.

Use the selected accent family. Default Teal reference tokens are canvas `#F7F7F4` / `#101B24`, panel `#FFFFFF` / `#192934`, text `#1B2D36` / `#EBF1F2`, secondary `#586970` / `#ADBDC4`, accent `#126D70` / `#65C7BC`, and selected fill `#E2F1EE` / `#20454A`. Consume shared theme values; do not hardcode these samples into feature widgets.

Use Roboto, 24–28 sp screen titles, 16 sp names/body and 12–13 sp metadata. Reserve monospace for the advanced schedule expression and technical error details. Use 16 dp gutters, a 4 dp spacing grid, 8 dp group/menu corners, 6 dp action corners, thin dividers and minimum 48 dp targets. Let labels and rows grow.

Conceptual list, using illustrative content:

```text
‹  Scheduled tasks
● Home server / Personal

[ Search tasks                          ]
 All   Active   Paused   Needs attention

 Morning briefing                     ⋮
 Tomorrow, 09:00              Scheduled
 Weekdays · Saved on server
 ──────────────────────────────────────
 Weekly review                        ⋮
 Monday, 18:00                   Paused
 Weekly · Telegram

                         [+ New task]
```

- Filters use background selection only; no ticks/radio dots. On narrow widths they scroll or reflow without truncating their meaning.
- Sort running/attention tasks first, then scheduled tasks by actual next-run timestamp, then paused/completed tasks with stable title ordering. Search and filtering do not mutate saved task state.
- One compact ellipsis per row, using the existing opaque anchored popup: Edit, Pause/Resume, Run now, Delete. Row tap opens details. Do not put live switches beside the disclosure.
- Place a compact, reachable labeled New task action at the bottom with safe-area and final-row clearance. Match shared action geometry; do not change the existing Chats button.
- Detail: title/status, next run, grouped cadence/last run/delivery/model facts, readable instructions, recent runs. Edit lives in the header; Run now and Pause/Resume form a compact reachable action area. Destructive action stays in the menu.
- Editor: dedicated full-screen route, sections “Task”, “Schedule”, “Results”, “Model”; concise grouped rows open short choice sheets. Instructions grow and scroll. Save stays reachable above the keyboard without covering the final field. Warn before discarding unsaved edits.
- Schedule changes show a plain-language summary. The custom expression is an advanced disclosure. Explicitly label recurrence versus one-time execution.
- Results use `StudioSelectionTile` with selected fills. Label `local` as **Save on server**, never “This phone”. Describe this as server result storage; conversation availability is a separate fact.
- Use `StudioSelect`, `StudioActionLabel`, `StudioError`/`AdminNotice.error`, and existing model-picker components. Pending actions retain their label/width. No custom font, gradient, hero artwork or new accent palette.
- Empty: “No scheduled tasks for this profile.” with New task. Search-empty has Clear filters. Failures are not rendered as empty lists. A saved task whose scheduler registration failed gets an attention state with the returned task identity.
- Status uses readable text plus a small glyph; color is supplementary. Use semantic error colors, no tick icons. Motion is limited to ordinary route/control transitions and required progress feedback.

## Backend contract and correctness

Always provide the captured canonical `profile` query on task operations, including GET and DELETE; URL-encode task IDs. Never rely on the list's `all` default or the backend's owner-discovery behavior.

| Action | Contract |
| --- | --- |
| List | `GET /api/cron/jobs?profile=P` → JSON list (existing Android wrapper exposes `data`) |
| Detail | `GET /api/cron/jobs/ID?profile=P` |
| Create | `POST /api/cron/jobs?profile=P` with current creation fields |
| Edit | `PUT /api/cron/jobs/ID?profile=P` with `{updates: {...}}` |
| Pause/resume/run | `POST /api/cron/jobs/ID/{pause,resume,trigger}?profile=P` |
| Delete | `DELETE /api/cron/jobs/ID?profile=P` |
| Runs | `GET /api/cron/jobs/ID/runs?profile=P&limit=20` → `{runs, limit}` |
| Delivery | `GET /api/cron/delivery-targets` → `{targets}`; verify deployment routing before claiming these are selected-profile destinations |
| Templates | `GET /api/cron/blueprints`; `POST /api/cron/blueprints/instantiate?profile=P` with `{blueprint, values}` |

Specific requirements:

1. Parse current `schedule.kind` discriminants: `cron` uses `expr`, `interval` uses `minutes`, `once` uses `run_at`. Treat `schedule_display` as display text, not an editable expression. Do not submit unchanged schedules: resubmitting a relative one-shot or interval can move its anchor.
2. Use server-returned `next_run_at` as authority. Recurrences follow Hermes' effective timezone, which can be set by environment or configuration. A config value alone does not prove the effective zone. Show “Hermes timezone” when its name cannot be verified; optionally show the returned instant in labeled phone time. Never infer an IANA zone from an offset. One-time date/time chosen in phone time is sent as an explicit UTC instant; label that choice. No per-job timezone editor is supported by the studied create API.
3. Use a required current `state`; unknown/incomplete states display as unavailable and do not acquire invented mutation eligibility. Handle scheduled/running/paused/completed/error states and enabled facts without importing desktop's legacy inference paths.
4. Send model/provider together when changing the override; clearing both means use the profile's model at execution time. Existing advanced fields (`script`, `no_agent`, skills, context sources, base URL, workdir, toolsets) are outside the common-field patch. Do not force a prompt onto script-only or skill-backed tasks. Unsupported execution editing is read-only with a precise explanation.
5. Delivery discovery includes configured platforms that may lack a home channel. Show that condition and require configuration before selecting such a destination for a new route. Never treat a discovery failure as an empty supported catalog or silently rewrite existing destinations. The studied delivery endpoint does not declare a profile parameter; selected-profile routing needs a focused acceptance check.
6. Run-now is synchronous and can outlast Android's 45-second administration timeout. Add a dedicated trigger timeout matching the desktop contract and a task action controller that outlives the detail route. Keep other operation timeouts unchanged. Do not label request submission as run completion. Leaving the page must not cancel the server operation or enable duplicate submission on reopening it.
7. A connection loss/app restart after a write can leave the outcome unknown. Reconcile by reading task/run state. Do not automatically replay create/trigger, or present “Retry run” as if no run happened. If state cannot establish the outcome, retain an explicit uncertainty notice; do not promise exactly-once execution without an idempotency contract.
8. Running a paused task may resume it. Use an explicit “Resume and run” confirmation that states both effects. Pausing is not stopping an already running task. Do not offer Stop unless a verified task-specific contract is added in a separately approved scope.
9. Preserve structured mutation HTTP errors: validation errors, 409 already-running conflicts, and 424 partial creation where a job was saved but external registration failed. Re-read returned task identity after partial creation rather than creating it again. Sanitize error presentation; do not log credentials/prompt bodies.
10. Confirm writes using responses and readback. Report successful mutation plus failed refresh separately. A finished one-shot can disappear from the task list; reconcile its recent runs and avoid resurrecting it from the trigger response.
11. Refresh on entry/resume, after mutations and manually; poll a visible running detail at a bounded cadence (initial proposal 8 seconds), suspending when backgrounded or offline. This is one current refresh policy, not an older-backend compatibility path. Request generations fence stale results across scope changes/disposal.
12. Run rows open `ProfileSessionKey(capturedScope, returnedSessionId)` via existing navigation. Cron sessions remain reachable from this explicit path even with automated chats hidden in Chats. Preserve that user's filter and any existing drafts. Do not infer success solely from a session's `ended_at` or synthesize session IDs.
13. Templates use server-provided text and typed fields, never a copied catalog. Explicitly choose Save on server for this administration context, which has no originating chat. Surface unsupported field types as unavailable rather than guessing their serialization. Template discovery failure does not hide manual creation.

## Implementation sequence and file boundaries

Before coding, run `git diff --stat fd5c1c7..HEAD -- lib test integration_test docs plans` and inspect any changes in the seams above. Existing user edits in privacy/notification/bug documentation are unrelated and must remain intact. Do not commit, push, deploy or mutate a live server as part of this planning request.

1. **Contract and state layer.** Add `lib/core/models/scheduled_task.dart`, `lib/core/services/scheduled_tasks_repository.dart` and `scheduled_tasks_controller.dart`. Build on `ProfileAdministration`; extend its transport seam only as needed for structured errors and the trigger timeout. Remove the unused unscoped cron helper methods and update their direct tests instead of adding compatibility wrappers. Add `test/scheduled_tasks_repository_test.dart`, `scheduled_tasks_controller_test.dart`, and `scheduled_tasks_transport_test.dart`.
   Verification: `flutter test test/scheduled_tasks_repository_test.dart test/scheduled_tasks_controller_test.dart test/scheduled_tasks_transport_test.dart` → all pass against current-contract fixtures.
2. **Inventory and detail.** Add `lib/core/screens/administration/admin_scheduled_tasks_page.dart` and `admin_scheduled_task_detail_page.dart`; wire the destination/search in `administration_content.dart`. Pass a scoped session-navigation callback from the existing shell if required; keep controller ownership explicit. Extend `test/support/administration_fixture.dart`, `administration_navigation_test.dart`, and add `scheduled_tasks_screens_test.dart`.
   Verification: `flutter test test/administration_navigation_test.dart test/scheduled_tasks_screens_test.dart` → ownership, detail navigation and state tests pass.
3. **Editing and operations.** Add `admin_scheduled_task_editor_page.dart`, schedule serialization tests, and action/uncertainty cases. Reuse Studio controls and model selection. Add templates as a secondary creation route only after manual creation and result reconciliation work.
   Verification: `flutter test test/scheduled_tasks_screens_test.dart test/scheduled_tasks_repository_test.dart test/scheduled_tasks_controller_test.dart test/scheduled_tasks_transport_test.dart test/studio_selection_test.dart` → all pass, including no accidental re-anchoring or cross-profile mutation.
4. **Rendered design and integration.** Extend captures following `test/administration_navigation_test.dart` and `docs/TESTING.md`; add a dedicated test/render entry for the new screens if it keeps that file focused. Inspect actual Flutter light/dark renders with Roboto, all five accents, 320 dp at 200% text, long names, keyboard-open editor, pending/error/empty states and large inventories. Check native keyboard, back navigation, accessibility actions, touch boundaries and resume behavior on an emulator. Add an opt-in `integration_test/scheduled_tasks_live_test.dart` for an explicitly authorized disposable profile/server; document mutations and cleanup before running it.
   Verification: `flutter analyze --fatal-infos`, `flutter test`, then `flutter build apk --debug` → clean analysis, passing tests and successful debug build. Run tests and build sequentially. Renders and authorized live results remain separate acceptance evidence.
5. **Documentation.** Update `docs/ADMINISTRATION.md`, `docs/ADMINISTRATION_ROADMAP.md`, `docs/FEATURES.md`, `docs/design/2026-09-14-administration-handoff.md` and `docs/TESTING.md` to reflect only delivered behavior, ownership and limits. Mark this plan done only after its acceptance criteria are established; record untested live behavior plainly.

The scoped implementation may also change `connection_manager.dart`, `administration_repository.dart`, their direct tests, and the existing app-shell file that supplies conversation navigation. Do not refactor unrelated authentication, notification, conversation or theme behavior. No backend source patches are included. If a dependency is needed for schedule handling, first establish why the server contract and existing Flutter date/time controls are insufficient.

## Required regression cases

- Explicit profile on every request; two connections with matching task IDs; profile deleted mid-edit; selection changes and late reads/writes; encoded IDs and prefixed dashboard URLs.
- Bare list decoding, malformed current responses, validation detail, 409 conflict, 424 saved-but-unregistered, offline/stale list versus confirmed empty.
- Cron/interval/one-shot parsing; every weekday/time control; clear recurrence labels; DST-boundary returned timestamps; phone zone different from Hermes; unchanged schedule omitted from edit; unknown zone not guessed.
- Minimal updates for advanced jobs, script-only/skill-backed prompt validation, paired model clearing, catalog failure without clearing saved choices, destinations missing home channels.
- Double-tap run, run longer than 45 seconds using a controlled async fixture, leaving/reopening detail, failed refresh after successful mutation, lost acknowledgement, completed one-shot disappearance, history read failure and script-only empty history.
- Scoped conversation navigation while automated chats are hidden; no filter/draft changes; template typed values and unsupported fields; cancel/discard and failed-save draft retention.
- Render states in both themes, all accent families, 200% text at 320 dp, large task counts, keyboard insets, focus, merged semantics, 48 dp targets, tick-free selections and scroll reachability.

## Stop conditions and approval boundary

The owner approved implementation on 2026-09-17. Routine design/code choices within this scope need no repeated approval. The owner emphasized delightful scheduled-task screens and explicitly excluded redesigning the rest of administration.

Report a concrete contract gap rather than inventing support if the target server lacks these routes, effective delivery scope cannot be established, or a new backend operation is needed. Do not add compatibility behavior without the owner's explicit approval. A missing effective timezone name is handled by truthful labeling, not by guessing. Live mutations require an explicitly authorized disposable target; fixture success is not live acceptance.

## Done criteria

- [x] Profile destination and settings search open the captured selected profile's tasks.
- [x] Core operations, editor, template creation and recent-run navigation meet the contracts above.
- [x] The new repository/controller/transport/screen tests pass, including asynchronous ownership and uncertain-write cases.
- [x] Clean static analysis, passing focused tests and successful normal debug APK build. The original full-suite-green criterion is superseded by the owner's instruction below; unrelated failures remain disclosed.
- [x] Actual Flutter renders and native checks reviewed against Studio; generated concept images do not count.
- [x] Live acceptance and its precise limits recorded separately.
- [x] Documentation reflects implemented features and plan index status reflects completion.

## Verification record — 17 September 2026

The owner explicitly requested proportionate verification and no repeated full-suite
runs for micro changes. One full run produced 1,896 passes, 11 skips and three
failures. The affected app-shell navigation test now waits for scrolling to
settle and passes in the focused run. The other two failures are unrelated
`support_wing_section_test.dart` large-text semantics checks (an offscreen button
is reported hidden); Support Wing source/tests were left untouched. This is not
a claim that the entire repository suite is green.

- Final focused run: 72 passes across scheduled-task model/repository,
  controller, transport and screen tests, administration navigation, shell
  navigation and Studio selection. Earlier focused passes also covered the
  required-input, unchanged one-shot and growing-title fixes. The final small
  completed/disabled status-copy correction was checked by analysis/build.
- `flutter analyze --no-pub --fatal-infos`: no issues.
- `flutter build apk --debug --no-pub`: success; normal app entry point restored
  after native integration testing.
- Reviewed real Flutter captures under `build/scheduled-tasks-review/`: light
  and dark inventory/detail/editor, all five accents, 320 dp with 200% text,
  expanded navigation titles and keyboard-reserved editor space.
- `integration_test/scheduled_tasks_native_test.dart`: passed on disposable
  API 36 emulator `emulator-5556`, exercising creation, real keyboard, anchored
  pause menu, detail and back navigation. It uses the production UI with an
  in-memory transport, not a live model.
- `test/scheduled_tasks_live_test.dart`: passed against unchanged Hermes
  `af4a3eba0a3674633050bf1c41df45f8ed6f0858`, loopback port 9847 and isolated
  `/tmp/wing-scheduled-live` data. Verified scoped CRUD, schedule changes,
  pause/resume, template instantiation, delivery catalog and harmless script
  execution through the production HTTP transport. Execution database reported
  completed with no error; all test-owned jobs were removed.

Paid model inference, external messaging delivery and every provider's catalog
were not exercised live. Delivery discovery is connected-server discovery,
not evidence that each selected profile owns every destination. The live driver
lives in `test/` so it can run directly against a disposable loopback server;
the native driver remains in `integration_test/`.

Maintenance focus: scheduler API revisions, trigger execution semantics, effective profile routing, timezone exposure, run-history limits and template field schemas. Do not broaden this feature into a second scheduler or silently switch contracts as those evolve.
