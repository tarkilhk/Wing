# Make Wing straightforward to change

Planning date: 3 October 2026. Planned against Wing commit `a5650fa675209b6a782a5adf3f39ff12c53efb4c`. Status: **COMPLETE; started by the user on 3 October and accepted on 6 October 2026**. Final production source: `8af0db73b446f2c0d12f9e31afb08a870a4e5a11`. See [the closure index](README.md) for accepted scopes and evidence bindings. Priority: architecture first. The original plan and completion criteria below are retained as the execution contract.

## Outcome

Wing has one authoritative owner for each business fact and workflow. Widgets display observations and submit user intent. Business rules, transport schemas, persistence, asynchronous reconciliation and operation lifetimes live behind small, testable interfaces. All dead code in the application checkout is removed, including dead members, branches, tests, tools, assets and direct dependencies. Automated guards prevent discovered bad patterns from returning wherever a dependable check is possible.

This is an architecture program with defect fixes and deletion work inside it. Resolving the original review's 18 findings alone does not establish completion. Every production feature must pass the ownership inventory, and the whole authored checkout must pass the dead-code inventory.

Execution root: `/home/dev/projects/hermes-android/hermes-android`. Sibling prototypes and the backend checkout are references, outside the removal/migration scope. Read root/project `AGENTS.md`, `CONTRIBUTING.md`, `docs/DESIGN_SYSTEM.md`, `docs/TESTING.md`, `docs/PERFORMANCE.md`, and the administration ownership handoff before the affected work. Preserve Studio appearance, supported behavior, ownership, offline work and uncertainty handling.

Use [verification and prevention contracts](001-clean-architecture-verification.md) for the mandatory tests, guards and acceptance journeys. Use [the reusable guard-writing skill](../tools/agent_skills/create-regression-guards/SKILL.md) whenever a new incorrect pattern is discovered. The skill is repository-local: pass its path explicitly to future agents; it is not globally installed.

## Constraints and reference decisions

Wing targets current upstream **unmodified** Hermes. The original audit inspected `bd0affe5e5f723579df8902852f5d0c47795f355`; this planning pass refreshed upstream main to [`c8301ea6c9b797184df16a9c5dd462400b264ff4`](https://github.com/NousResearch/hermes-agent/commit/c8301ea6c9b797184df16a9c5dd462400b264ff4) and read pinned `hermes_cli/web_routers/cron.py`, `tui_gateway/methods_session.py` and `tui_gateway/methods_prompt.py`. Cron profile parameters still act as hints and can resolve another owner. The standard conversation methods remain `session.create`, `session.resume` and `prompt.submit`. Verify and record latest upstream again before each contract change; never implement an assumed capability from a fixture or older deployment.

Implement client changes only. Backend patches, plugins, custom endpoints, deployments and provider/model side effects are outside this plan's implementation authorization. Obtain the required authorization for a live acceptance target and owned fixtures before running mutating journeys. Do not upgrade a user's deployed server as a prerequisite without separate authorization.

Prefer direct, clean replacements: update callers and remove superseded interfaces in the same accepted batch. Backward-compatibility behavior requires explicit user approval, including old defaults, aliases, format readers, flags and migration shims. This plan does not authorize those. Avoid changing persisted formats merely to reorganize code; a necessary format change must state its data consequences before implementation.

Flutter's official [architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations) guide the separation of UI/data, immutable observations, dependency injection and testable commands. The [architecture guide](https://docs.flutter.dev/app-architecture/guide) supports an optional domain layer for complex or repeated workflows. Our project-specific choices are constructor injection, existing `ChangeNotifier`/`Listenable`, feature repositories and cohesive coordinators. Introduce abstraction where production I/O and a behavioral fake genuinely vary; implement ordinary pure rules as functions/value types. Keep the pinned Flutter 3.44.0/Dart 3.12 toolchain. Package, router and code-generation changes must earn their complexity through a concrete requirement.

The official [Lauren Tan pstack](https://github.com/cursor/plugins/tree/main/pstack) principles used here are subtract before adding, minimize reader load, model independent domain facts, respect interfaces, and test behavior. The literal `poteto/pstack` repository was unavailable during the audit; provenance is recorded in the existing review.

## Current architecture: evidence to check before execution

These source excerpts were inspected for this plan. Recheck the relevant code against the live revision before a batch; line numbers from the older audit can drift.

| Source | Current behavior | Architecture consequence |
| --- | --- | --- |
| `lib/core/services/profile_workspace_controller.dart` | Imports `../widgets/chat_intelligence_picker.dart` and `../widgets/model_chooser.dart` | Domain identity/parsing is coupled to rendering libraries |
| `lib/core/services/administration_health_session.dart` | Imports `../widgets/profile_diagnostics_panel.dart` | Retained business work depends on a widget-owned controller |
| `lib/core/models/chat_list_view.dart` | Imports the workspace controller; `chatListStatus(..., ProfileChat? chat, ...)` | A shared domain projection depends on mutable orchestration |
| `lib/core/widgets/slash_command_suggestions.dart` | `_select`: `widget.chat.draft = text;` | A UI path bypasses the persistence owner |
| `lib/core/screens/profile_transcript.dart` | `chat.notificationFocus = null;` after locating its anchor | The view clears application routing state directly |
| `lib/core/services/scheduled_tasks_controller.dart` | `repository.update(original.id, original.changes(values))` | Save semantics rely on callers supplying the correct baseline |
| `lib/core/screens/administration/admin_scheduled_task_editor_page.dart` | `late final name = TextEditingController(text: widget.original?.name ?? '');` and `controller.save(values, original: widget.original)` | Retained UI inputs and refreshed business baseline can disagree |
| `lib/core/widgets/profile_default_model_sheet.dart` | Reads `model/info` and `model/options`, posts `model/set`, handles confirmation, then reads back | Widget owns a complete business workflow |
| `lib/core/screens/administration/admin_settings_page.dart` | Computes sparse changes, rereads configuration and detects conflicts inside `_save` | Business edit-session ownership is in rendering code |
| `lib/core/screens/administration/admin_providers_page.dart` | `_timer = Timer(Duration(seconds: interval), _poll)` inside the OAuth widget | Business session lifetime is tied to a rendering implementation |

Exemplars worth retaining: `ProfileGateway` captures canonical `WorkspaceScope`; `ScheduledTasksRepository` wraps task operations; `ScheduledTasksController` has disposal generations, busy/uncertain state and journal-before-mutation; `ComposerDraftStore` orders per-record persistence; registry/route leases distinguish application lifetime from a screen; the voice repository already owns meaningful shared behavior. These are starting points to sharpen, not reasons to build duplicate layers.

The codebase advanced after the audit through notification decision handling. Phase 0 must reconcile that work and preserve it. Historical counts (2,816 passing Flutter tests, 17 skips, 9 native tests, 97 Python tests) describe the earlier audit snapshot; they are not results for this plan or a target count to preserve after deleting obsolete tests.

## Target ownership and dependency rules

Names below describe optional responsibilities, not a mandatory seven-layer pipeline. A simple feature may need only an immutable model, an existing adapter, a controller and a view. For each fact explicitly select its canonical repository/coordinator owner; presentation observations derive from that owner rather than duplicating business state. Retain an existing name when it accurately describes the owner. A rename or new class is justified by clearer ownership, not by this table alone.

| Module | Owns | Exposes |
| --- | --- | --- |
| Domain values and projections | Canonical identities, execution facts, pending-input facts, model selections, schedule values, transcript semantics, validation and comparisons | Immutable values; pure functions; no transport, controller, persistence or rendering dependencies |
| Transport/platform adapters | Authenticated scoped HTTP/RPC, sockets, storage access, platform channels, native resource acquisition | Typed results and bounded asynchronous operations; transport details private to the adapter |
| Feature repositories | Authoritative domain records, refresh/cache policies, acknowledged data changes and persistence coordination | Read-only observations and explicit mutations through real injectable I/O seams |
| Workflow coordinators | Multi-step operations, revisions, conflicts, uncertainty, queue ordering and lifetime-sensitive reconciliation | Commands and observable outcomes; no `BuildContext` or widget controllers |
| Presentation controllers/view models | UI observations, filtering/formatting, command availability and UI-facing error/loading state | Narrow read-only screen state and intent callbacks |
| Views | Layout, animation, accessibility, focus, text/scroll controllers, local expansion, dialogs and simple navigation | Render observations; submit edits/decisions through commands |
| Composition and lifetime owners | Construct/share/release dependencies and route/application leases | Wiring; business policy belongs to the feature owner |

Enforce unidirectional flow: user intent enters a command; its owner validates/applies the operation; new observations flow to presentation. Immutable collections must be protected deeply enough that a view cannot mutate nested state. Internal mutable structures may remain private to their one owner.

Models cannot import controllers, data adapters or Wing UI. Repositories/coordinators cannot import screens/widgets, Material rendering, routes or UI controllers. Feature views cannot construct stock endpoints, parse response schemas, open raw storage/HTTP/native channels, or write business fields. Composition may construct both sides but must remain wiring. Genuine UI-only state is allowed: scroll position, selected tabs, animation and text selection. Durability, scheduling policy, approval outcomes and notification acknowledgement are business behavior.

Framework utility use is classified by purpose. Do not mistake Unicode character helpers, lifecycle adapters or `foundation` notifications for widget business logic. Keep lifecycle/platform glue narrow, with an explicitly owned interface.

Implement a Dart graph that normalizes/resolves library identities from parsed import/export/part/conditional-import directives. Full symbol resolution is reserved for rules whose property needs it. Count `part` files as their containing library, without hiding dependencies by arbitrary file grouping. Zero authored-library dependency cycles is the final target. Declare feature roles for every authored library in `lib/`; generated code is outside ownership classification but its handwritten callers are included. A composition exemption must identify actual wiring, not permit a whole screen or `main.dart` to own business rules.

## Phase 0 — Establish a complete map and enforce the direction

Scope: every authored area in the application checkout, including `lib/`, native/platform sources and resources (Android and other checked-in platform roots), `test/`, `integration_test/`, `tools/`, `scripts/`, `.github/`, assets, root manifests/build declarations and direct dependencies. Enumerate tracked files plus intentional untracked source; exclude installed dependencies and build/cache output from declaration scans. This is a scope inventory, not permission to indiscriminately delete generated/vendor/platform files.

1. Record the source revision and existing worktree diff, inspect changed files and reconcile all review findings. Run the baseline commands in the verification document. Keep failing pre-existing checks visible and understand them before extraction.
2. Classify every authored Dart library by feature and architectural role. Record every UI-owned business workflow, every cross-layer/cyclic dependency, and each mutable fact's current owner and callers. Include app-shell/setup/notification routing, browser, conversation, administration, voice, attachments and viewers. A zero-results search is only a lead; read each screen/widget library.
3. Build the runtime-root inventory: application entry point, native manifest and callbacks, channel method strings, plugin registration, alternate supported test/performance entry points, scripts/CI entry points and resource loading. Generate whole-file and member-level candidates for deletion.
4. Create small independent architecture linters, proposed location `tools/architecture/rules/`, one precise property per file/command with its own bad/valid fixtures. `tools/architecture/check_all.dart` is only a lightweight aggregate runner; `test/architecture_contract_test.dart` exercises the rule contracts. Share cheap parsing helpers where useful; resolve symbols only for rules that require them. Add a direct development dependency on a compatible analyzer version if required; do not rely on an undeclared transitive dependency. Reuse standard lints first. Checks are deterministic, offline and fast; measure individual and aggregate runtime and establish explicit justified local-feedback budgets before rolling the pattern out. Acceptance benchmarks must remain within those budgets on the recorded host/configuration; optimize measured regressions rather than silently raising the budgets. Changed-file runs must include affected import/caller closure, while CI runs the full scope.
5. Capture exact current violations as a finite migration baseline. Reject new violations immediately. Remove entries as their slices migrate. Final acceptance requires an empty baseline, no broad suppressions and no omitted features. This is tooling state, not a product compatibility path.
6. Add the missing offline `tools/qa` test discovery to PR/relevant release checks and wire new architecture checks into the existing workflow without duplicating existing build/native/renderer jobs.

Deliverables: `docs/ARCHITECTURE.md` with roles/ownership/interfaces; machine-readable role/root/baseline data under `tools/architecture/`; an auditable deletion inventory and feature checklist under this plan's execution index; red/valid guard fixtures. Keep operational evidence in ignored `build/`, performance evidence in the private archive required by `docs/PERFORMANCE.md`. These files are proposed execution artifacts, not present-day results.

Gate: baseline commands have explicit outcomes; every production library and UI feature is classified; root/candidate inventory covers all scoped areas; guard fixtures fail/pass as intended; a deliberately broken synthetic fixture causes the guard command and CI gate to exit nonzero. No architecture migration starts from an unclassified feature.

## Phase 1 — Protect ownership before restructuring

Scope: active workspace/draft/snapshot/task owners and their existing behavioral tests. Keep these fixes separate from structural moves.

1. Promote the three temporary reproductions into permanent tests through the active controller and real task route. Existing scratch files in `/tmp` are hints; execution must not depend on their availability.
2. Fix stale resume reconciliation using captured identity/runtime/revision; cover open, reconnect and queue recovery. Do not reject every response blindly: valid identity and snapshot information still needs reconciliation.
3. Make shared-draft rollback revision-owned, including staged file cleanup. A failure may undo only work the failed operation still owns.
4. Send slash completion through the authoritative draft command. Treat cursor/suffix manipulation as presentation while durable text commit remains owned.
5. Publish confirmed deletion/tombstones independently of failed local cleanup; cleanup retry never repeats the server deletion.
6. Protect the scheduled edit baseline and only submit user-edited fields. Add current-owner checks and scoped membership preflight. Preserve uncertainty and explicitly document the remaining preflight/dispatch race: stock Hermes lacks an atomic expected-owner condition.
7. Preserve hidden rows and typed notice display metadata in bounded reading snapshots. Restore reading information without restoring runtime authority or pending decision permission.
8. For every issue, implement the feasible prevention guard from the companion catalog, or record why static detection is unreliable and link the deterministic behavioral guard. Compiler-enforced private state is a valid structural guard.

Gate: each original defect has a failing-then-passing regression; untouched/newer facts survive delayed/failing I/O; no blind resend or invented backend guarantee; affected widget/controller tests and analyzer pass. The task editor may receive its baseline fix now and have its full ownership extracted in phase 3.

## Phase 2 — Subtract dead paths and eliminate dependency inversions

Scope: inactive chat members, experimental fixture recovery protocol, model-choice/intelligence types, diagnostics and status projection dependencies. Follow the root-aware deletion procedure below.

Delete inactive `ApiClient`, `GatewayChatClient`, high-level `WsClient` chat orchestration and supporting fields/subscriptions that have no active caller. Preserve the shipping `ProfileGateway` path, low-level socket transport, authentication, RPC correlation, global events and outbox behavior. Move relevant assertions to active seams; tests solely describing deleted implementations disappear with them.

Remove the unused ledger protocol from `tools/fake_gateway/turn_recovery_contract.py` and its normal fixture coupling. Keep stock-shaped fixture behavior and deterministic disconnect tests. Do not let the fixture advertise `session.open`, `turn.reconcile` or versioned submission as current upstream capabilities without verified support.

Move `ModelChoice`, intelligence identity/value types and parsing to their appropriate model/data owner. Move `ProfileDiagnosticsController` out of the widget library and pass captured scope/typed observations instead of the whole mutable workspace. Make `chatListStatus` accept immutable domain observations rather than `ProfileChat`. Switch all imports; remove old exports/forwarding aliases in the accepted batch.

Additional member candidates already identified, to prove against all roots before deletion: `GatewayInterimTransition`, `GatewayNotification`/`GatewayNotificationLevel`, `GatewayTurnStatus`, `WingStatus`/`colorForStatus`; unused `AttachmentDraftMode.rest` and exclusive limits/branches; the unused direct `highlight` dependency. Dedicated tests do not make an otherwise inactive production member live. Keep shared live members in those same files. Remove a direct dependency only after checking native/assets/tooling use, then regenerate the lockfile through normal dependency resolution.

Gate: named dead paths and their exclusively supporting code/tests are absent; surviving transport/notification/outbox tests pass; migrated model-selection and diagnostics owners have zero service-to-UI inversions; the extracted status projection accepts only immutable domain observations. The owner-bearing `ChatListEntry`/`ChatListGroup` projections in `chat_list_view.dart` retain their explicit model-to-controller baseline entry until the coordinated Phase 5 browser ownership migration; do not reclassify the file to hide it. Dependency counts do not increase through new forwarding layers. Rerun candidate generation after the deletion cascade.

## Phase 3 — Prove the architecture with a complete feature

Scope: scheduled tasks as the first vertical slice, then diagnostics/model configuration. Design the feature interface before moving code; inspect an alternative shape and choose the one with fewer caller obligations.

Create a scheduled-task edit-session owner that captures canonical scope, a stable opening baseline, edited fields and current server observations. It owns schedule semantics, future-time validation, required destination/template fields, sparse update construction, conflict checks, confirmed/uncertain save outcomes and cancellation/disposal generations. The view owns input controllers and picker presentation. Expose typed state and commands such as edit/validate/save/reconcile; exact method names should follow existing vocabulary.

Keep business validation independent of `FormState`: a form displays validation errors produced by the owner. Server validation remains authoritative. A refresh cannot rewrite the edit baseline or silently replace dirty input. Same-field conflict resolution produces explicit user intent through a command; dialogs remain in the view.

Finish diagnostics extraction and consolidate profile/helper model configuration behind the existing scoped adapters. Keep session overrides distinct from profile defaults. The owner exposes confirmation-needed state, captures the pending selection and generation, then consumes the dialog decision. The widget neither builds a request nor implements readback/conflict policy.

Gate: controller/domain tests execute workflows without constructing a widget; actual route/widget tests prove field editing, errors, confirmation, dirty-pop guards and navigation; restart/scope/disposal scenarios are covered; these features have zero UI business inventory items and zero architecture violations. Review the pilot for reader load before copying its structure across the app.

## Phase 4 — Migrate every remaining feature slice

Scope: the complete phase-0 UI inventory. Execute one coherent feature at a time, not one file at a time. These are confirmed starting slices; discovery may add work.

| Slice | Current entry points | Move to the owner |
| --- | --- | --- |
| Capabilities/tool setup | `profile_capabilities_screen.dart`, `admin_tool_setup_page.dart` | Schema validation, eligibility/readiness, scoped enable/write/readback, skill loading |
| Provider/MCP auth | `admin_providers_page.dart`, `admin_connectors_page.dart`, existing provider/OAuth modules | OAuth sessions, polling/cancellation, credential/profile ownership, acknowledgement/readback |
| Configuration/defaults | `admin_settings_page.dart`, `admin_defaults_page.dart` | Typed schemas, pure setting comparisons, edit baseline, sparse writes, conflicts and acknowledgement |
| Identity/skills/library | `admin_identity_page.dart`, `admin_skills_page.dart`, related hubs | Identity/content parsing, captured edit sessions, mutations and readback |
| Voice configuration/synthesis | `admin_speech_synthesis_page.dart`, profile voice pages | Provider/setup workflows and operation lifetime; reuse `ProfileVoiceRepository` |
| Health/operations/usage | administration health, operations and dashboard pages | Business polling, retained observations, command outcomes and domain aggregation |
| App shell/setup/notifications | `lib/main.dart`, connection/setup/routing UI | Connection business operations, decision handling and destination policy outside rendering; preserve the recent notification fixes |
| Browser/history/search | workspace browser and history/Recents UI | Route core ownership/projection work through phase 5 once; local menu/filter presentation remains UI |
| Composer/attachments/viewers | conversation UI and remaining widgets/screens | Route composer/outbox/history ownership through phase 5 once; migrate independent attachment/viewer workflows here, with resource work in phase 6 |

For each slice: characterize behavior; define the small interface and owner; move policy/parsing/I/O; wire the real and fake adapters through constructors; switch every caller; delete the old implementation and exclusive tests; create or extend the feasible guards; remove baseline entries; run focused gates. Rewrite domain assertions at the new seam, while retaining view interaction tests. Avoid both duplicate ownership and tests that merely reproduce implementation details.

Every migrated business controller must define applicable scope capture, request generations, operation outcomes, duplicate submission handling, uncertainty behavior, lifetime and disposal. Pure presentation controllers do not acquire journals or business operation machinery for uniformity. An operation outlives a route only when an application-owned owner deliberately retains it. UI form state may have an independent lifetime, but cannot decide whether a pending server write is confirmed.

Gate per slice: no direct low-level transport/storage/channel usage; no response-map parsing or semantic mutation policy in its views; read-only business observations; owner tests plus real route tests pass; no old path remains. Core browser/history/composer slices are assigned to phase 5 and never extracted twice. Phase 4's final feature-inventory gate waits for those phase-5 acceptances: all production features are migrated or were reviewed and already satisfy the target; no unexplained inventory row remains.

## Phase 5 — Make conversation ownership explicit

Scope: workspace orchestration, runtime/events, composer/outbox, reading/history, browser mutations, attention and retention. This phase depends on characterization and the smaller-feature pilot. One editor/core ownership batch must be reviewed before the next extraction.

Represent independent facts independently: execution; connection/recovery; pending approvals/clarifications/secure input; submission/durability; presentation. Completion with an unresolved decision stays completed and still needs input. Clearing the final decision does not manufacture a running turn. Browser, Recents, composer availability, monitoring and notifications derive from the same attention observation.

Write the transition/ownership table before extraction. Include create/resume, delta, terminal, decision, navigation, deletion, disconnect/reconnect, queue dispatch, lost acknowledgement, replacement runtime, snapshot restore and disposal. Give each event one mutation owner and state which observations it invalidates. Test representative crossing sequences and adversarial delayed completions; do not create an enormous indiscriminate Cartesian-product suite.

Extract cohesive owners in this order unless the transition table demonstrates a safer dependency order:

1. Pure activity/attention projection and immutable identity/state values.
2. Composer/outbox owner: revisions, attachments, journal-before-dispatch, ordered writes, paused/uncertain items; one `ComposerDraftStore` seam.
3. Conversation reading owner: saved history, pagination, stable row semantics, snapshots/read state; snapshots never decide runtime execution.
4. Conversation runtime owner: active identity, live answer, execution/pending input, events and resume reconciliation; all event/read races pass through its reconciliation interface.
5. Workspace/browser and lifetime coordination: profile/project/session indexes, acknowledged list mutations, scope switching, gateway retention/recovery and leases.

The table must settle crossing operations explicitly: runtime replacement transfers draft work through the composer interface; deletion updates the browser's authoritative tombstone before optional composer cleanup; attention notification delivery consumes observations and acknowledges focus through a command. Keep the remaining workspace coordinator only where it orchestrates these interfaces. Private internals cannot remain shared mutable bags passed between the extracted owners.

A small number of real coordinating modules is preferable to a class for every verb. File length is a review signal, not an acceptance threshold. No "split" counts as architecture progress while widgets or peers can still mutate another owner's state.

Gate per extraction: existing outbox, streaming, snapshot, ownership, notification and retention contracts pass; no new disposal leak or cross-scope mutation; completed-plus-pending-input scenarios yield consistent projections everywhere; independent review confirms each fact has one writer. The central controller becomes wiring/coordination plus responsibilities it genuinely owns, with no hidden second implementations.

## Phase 6 — Bound resource work and finish measured performance issues

Scope: image sanitation, Android intake/voice, Markdown scanning/browser grouping and the transcript investigation. Read `docs/PERFORMANCE.md` before any recording/build used as measurement.

Images: validate header/dimensions/frame/allocation budgets before full decode; move decode/orientation/recompression to a bounded worker. Preserve metadata stripping, format, aggregate limits, cancellation and file ownership. Define explicit limits from existing product contracts and measured memory constraints, not arbitrary tiny limits that break valid attachments.

Android intake: separate potentially stalled provider acquisition/copy from durable queue operations. Use bounded work, deadlines/cancellation, late-result rejection and resource cleanup. A caller timeout alone does not release a hung executor. Prove a stalled provider cannot starve subsequent queue/share/camera/output work. Account for platform calls that cannot be reliably interrupted; surface that limitation and choose containment instead of claiming impossible cancellation.

Voice: move owned file transfers off the main thread, keep required recorder/player transitions on their correct thread, and verify generation/lifecycle before result delivery. Cover stop, Home, route/activity destruction and successive playback.

Markdown/browser: scan fences using original-string offsets and index occupied projects once. Preserve grammar/group output. Verify bounded operation growth; actual timing belongs to the measurement procedure.

Transcript: first instrument structure regrouping/key-map work at the existing opt-in seam. If material, reuse unchanged saved structure and reconcile the tail with explicit invalidation. If measurement shows no worthwhile benefit, close P03 as investigated with evidence. Preserve anchors, selection, history, grouping, late handoffs and saved widget identities. Measurement conclusions must name revision, device, mode and workload; host timings do not establish phone performance.

Gate: behavior/bounds/thread-work tests pass; applicable native journeys demonstrate cleanup and responsiveness; matched profile-mode phone runs satisfy the existing performance contracts and show no unexplained regression. Unavailable device evidence stays pending while independent source work proceeds.

## Phase 7 — Complete the dead-code sweep and prevention system

The deletion sweep runs during every earlier phase; this phase closes the whole-checkout inventory.

1. Regenerate file/member/branch/root/dependency/resource candidates after all migrations. Every candidate must end **deleted** or **retained with a demonstrated supported root/contract**. Zero unresolved candidates is mandatory. A retained candidate needs a concrete caller, registration, build variant or runnable supported tool, not "might be useful later."
2. Inspect test-only production members, unused enum cases, constructor options, impossible branches, abandoned mocks/fixtures, exports/barrels, orphan docs/scripts/CI steps, native resources and direct dependencies. Remove disabled experiments and superseded implementations without aliases or compatibility flags.
3. Check dynamic roots carefully: Android manifest, platform method strings, intent/actions/providers, XML/layout IDs, generated plugin/font/icon registration, JavaScript renderer loading, runtime-loaded assets, conditional imports and supported alternate entry points. Code absent from `main.dart` can still be live; a dependency used by Android or tooling can still be required.
4. Keep original attribution, licenses and required Flutter platform scaffolding. Generated/vendored content is classified through its owner/build use, not rewritten to achieve a smaller file count. Broad asset-directory declarations do not prove each file is used; resolve actual loaders and legitimate packaging.
5. Delete tests exclusive to removed behavior, but migrate shipping behavior assertions before deleting them. Expected test-count reduction is recorded by purpose. Existing supported native/performance tools must retain their runnable entry points and docs. Unsupported behavior needs a deliberate feature decision, not a silent dead-code label.
6. Remove empty folders, stale direct dependencies and obsolete instructions after code removal. Resolve dependencies normally; do not delete the lockfile or caches. Rerun full tests/build plus affected native/renderer journeys.
7. Make the architecture migration baseline empty. Ensure every discovered pattern has a tested static/structural guard when feasible, or a documented static infeasibility reason and a linked behavior/resource guard. Keep individual linters small and independently runnable; reuse helpers and extend an existing rule when it already covers the same property. The aggregate runner only discovers/invokes rules and propagates failures. Validate true positives, valid cases, deterministic output, measured runtime and CI exit propagation.

Gate: all authored areas/root categories were reviewed; every deletion has root/caller evidence; all confirmed dead code is removed; zero unresolved candidates and architecture violations; no legacy path kept for hypothetical future use; no broad exemptions; every new linter has its own behavioral fixture tests. Static tooling and manual dynamic-root review together support the claim; no tool alone proves arbitrary runtime unreachability.

## Phase 8 — Independent architecture and acceptance closure

Freeze the candidate revision/diff. Have fresh reviewers inspect module ownership/dependencies, adversarial concurrency/data loss, dead-code/root coverage, and native/contract verification. They review the resulting code, not just previous reports or test totals. Run independent passes in available slots with one shared-writer owner per overlapping change; read-only reviewers can operate in parallel.

Perform a change-locality exercise on at least three real examples: pending-input classification; a configuration/editor business rule; a stock response mapping. A reviewer traces each change from one authoritative owner to consumers and identifies its focused tests. Request schema or business-rule changes should not require copying rules across unrelated views. Run an actual small synthetic variant in a temporary worktree when inspection leaves uncertainty; discard it without changing product behavior.

Run final host/native/build/architecture/QA gates against the fixed candidate. Run the affected disposable-device journeys and authorized latest-stock contract acceptance. Inspect actual phone-size light/dark/enlarged-text renders. Verify permissions, route reentry, decisions, offline drafts/outbox, streaming/reading, task editing, voice and share cleanup as affected. Reuse `docs/TESTING.md` and the release checklist, including asset/license/release instrumentation checks. Do not publish/sign/deploy just to close this architecture goal.

Every final finding gets a fix and prevention decision, then the relevant checks rerun. Record exact skips and limits. If required environment evidence is unavailable, completion remains pending; do not replace it with a mock or waive it silently.

## The execution loop

For each smallest coherent batch: inspect current state and drift; select one owner/workflow; define invariant and observable outcome; reproduce/characterize; choose the simplest interface; implement; switch callers and delete superseded code; add/extend feasible lints using the guard-writing skill; run focused checks; independently review the diff and prevention guard; run broader checks at batch acceptance; update the phase/inventory index with evidence and remaining prerequisites.

Keep one source writer for workspace/conversation migrations. Bounded subagents may own a separate feature or shared-linter workstream with explicit paths and invariants. They return verified changes, tests and limits, not merely recommendations. Parallel checks/builds must respect the shared Flutter/Gradle toolchain and existing locks. Prefer independent worktrees when concurrent source edits are necessary. Preserve unrelated user changes, and never revert them to make checks green.

At loop boundaries record accepted batch, exact source/diff, next batch, guard added, validation and pending prerequisite in `plans/README.md`. Normal logs/captures stay ignored; update existing public architecture/feature guides only for durable contracts. Continue authorized work autonomously. Ask only when a real decision is necessary: compatibility/data loss, unsupported current-stock behavior, an unapproved external side effect, or a scope/product conflict. Ordinary refactoring choices and failing tests are reasons to investigate, not automatic permission requests.

## Final completion criteria and proposed goal

All of these must hold:

- Every authored production library/feature is classified and reviewed; zero UI-owned business workflows remain.
- Each durable/domain fact has one explicit writer; UI observes immutable/read-only state and invokes commands.
- Resolved dependency checks report zero cross-layer violations, authored-library cycles and remaining migration-baseline entries; all checks are CI enforced.
- All 18 review items are closed by a tested fix, deletion or evidence-backed investigation where the review explicitly calls for investigation. Newly found material issues are resolved, not omitted from the inventory.
- The complete dead-code inventory has zero unresolved candidates; all confirmed dead files/members/branches/tests/tools/assets/direct dependencies are removed; retained dynamic/tool roots have concrete evidence.
- Every discovered incorrect pattern has a tested automatic prevention guard wherever feasible; static infeasibility is explained and a meaningful alternative regression guard is linked. Guards reject representative bad code and accept valid cases.
- Existing supported behavior, stock scope, uncertainty/durability, retention and Studio interaction contracts pass the final fixed-revision host/build/native checks and applicable device/current-stock acceptance.
- Three change-locality examples and fresh architecture/dead-code/concurrency review pass without unresolved material findings. Documentation describes the resulting owners and how to change/test each feature.

Goal adopted by the user:

> Refactor the Wing application checkout into the ownership architecture in `plans/001-clean-architecture-program.md`: remove business workflows from every production view, give each domain fact one writer, remove all confirmed dead code across the fully reviewed checkout with zero unresolved reachability candidates, resolve the 18 review items and newly discovered material defects, and create tested CI-enforced prevention guards for every incorrect pattern where feasible. Complete only when the architecture baseline is empty, dependency/ownership and behavior checks pass, three change-locality examples pass independent review, and applicable native/device/latest-unmodified-Hermes acceptance has fixed-revision evidence. Preserve supported behavior and unrelated user changes; obtain decisions for compatibility, data-loss or unsupported-stock requirements and authorization for external side effects. Follow the plan's small-batch loop and report unavailable acceptance prerequisites honestly.

The user authorized execution after reviewing this document. The goal is complete;
accepted batches, final verification and scope limits are recorded in `plans/README.md`.
