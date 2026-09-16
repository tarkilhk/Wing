# Plan 003: Complete the administration experience redesign

Status: IN PROGRESS — owner authorized goal execution on 2026-09-17.

Worktree: `/home/dev/projects/hermes-android/administration-experience`; branch:
`codex/administration-experience`. Starting revision: `28b7f61`. The original
checkout remains available to the ongoing voice/project work. Fetch and integrate
completed main commits before final verification. The owner also authorized
redesigning incoming UI as needed for Studio consistency while retaining features.

Prepared 2026-09-17 at the owner's request. All ten review recommendations and
the clarification retaining Profile / Server / Health are accepted as the target.
Scheduled tasks are committed at `a84abda186ca2b495148fb33939d7a77e6fe0e53`.
Other concurrent work remains outside this preparation. Completion of that work
does not itself authorize changes to their working files. The owner has now
explicitly authorized this isolated implementation.

## Goal activation

Goal-tool state checked during preparation: no active goal. `create_goal`
immediately creates an active goal and provides no draft/pause parameter.
The goal was registered after the owner’s explicit go. No token budget was requested.

After the owner's explicit go, read the current goal state and create the
following goal only if there is no unfinished goal; reuse an already matching
goal. A conflicting unfinished goal requires resolution rather than replacement.

> Implement every accepted administration UX requirement R1–R10 in
> docs/design/2026-09-17-administration-experience.md in Wing, integrating the
> completed concurrent work and retaining Profile / Server / Health, Studio
> themes, truthful backend states and captured ownership. Complete all acceptance
> rows in plans/003-administration-experience.md with implementation references,
> passing targeted regressions, flutter analyze --fatal-infos, flutter test,
> flutter build apk --debug, inspected Flutter renders and native interaction
> evidence. Keep backend changes, compatibility shims and release/deployment out
> of scope; request the owner's decision for a necessary unsupported contract or
> compatibility behavior. Do not mark complete with omitted requirements or
> missing required evidence unless the owner explicitly changes the scope.

The documents were requested separately by the owner; they are implementation
planning artifacts, not a durable-state workflow imposed by the define-goal skill.

## Required reading and scope

- [Accepted design requirements](../docs/design/2026-09-17-administration-experience.md):
  authoritative requirement IDs, design direction and feature boundaries.
- [AGENTS.md](../AGENTS.md), [Studio](../docs/DESIGN_SYSTEM.md),
  [ownership handoff](../docs/design/2026-09-14-administration-handoff.md) and
  [Administration](../docs/ADMINISTRATION.md): current styling, ownership and contracts.
- [Plan 002](002-profile-scheduled-tasks.md): scheduled tasks are DONE at `a84abda`.
  Use its final verification record and committed source as the delivered baseline;
  its earlier prospective implementation notes are not a description of missing work.
- [Testing](../docs/TESTING.md) and [release checklist](../docs/CODE_QUALITY_CHECKLIST.md):
  distinguish fixture, native and live evidence. This goal is not a release.

The completion requirement is all accepted feedback, including conflict
comparison, full-screen Identity, capacity illustration, cost-share comparison,
search-to-field navigation and scheduled-task summary integration. Sequence is
not permission to drop the deeper changes after completing the overview.

## Committed scheduled-task integration baseline

Reviewed `a84abda` on 2026-09-17 after the owner's commit notification. The
repository/controller/model, list/detail/editor, shared task widgets, templates,
operations, search entry and scoped conversation navigation are already delivered.
Build on them; the redesign adds R1 summary presentation and R10 refinements rather
than rebuilding scheduling or repeating its completed implementation phases.

- `ScheduledTasksController.acquire/release` shares a controller by captured scope,
  retains the server repository and preserves in-flight operations across routes.
  An overview observer must balance leases/listeners when its profile changes and
  must not clear busy/uncertain state or create a competing action controller.
- The list currently refreshes every 30 seconds only while resumed, current,
  not loading and without a refresh error. Coordinate any overview refresh with
  that lifetime; avoid duplicate polling, offscreen refresh loops and reads on
  every build. Keep overview failures independent from other summaries.
- Derive next-run display from server timestamps for eligible known scheduled
  states. The first list row is not necessarily the next run: the list sorts
  running/attention items ahead of future schedules. Preserve phone-time labeling
  and distinguish no upcoming task from unavailable schedule data.
- `ScheduledTask` exposes `lastRun`, `error` and current state; `TaskRun` exposes
  conversation identity, start time and active state, not a verified success/failure
  result. Keep R1/R10's latest-outcome requirement, but display Outcome unavailable
  where no actual result is established. Never infer success from an ended/inactive
  conversation, a last-run timestamp or absence of an error. A completed one-shot
  may disappear from the inventory, so label any observation's limited coverage;
  do not claim it is the latest result across all historical tasks. Avoid per-task
  history fan-out merely to populate the root summary.
- `HermesAdministrationContent.onOpenSession` is now a required shell callback.
  Keep the existing `ProfileSessionKey` navigation and return-to-conversation flow,
  including runs opened while automated chats are filtered out of Chats.
- Keep existing schedule edits, paired model/provider changes, templates,
  delivery discovery, confirmations and uncertain-write safeguards intact.
  The populated-list introduction currently depends on text scale, not task count;
  reducing it when tasks exist remains an actual R10 change.

Plan 002 records 72 focused passes, clean analysis, a debug build, Flutter captures,
native fixture acceptance and isolated local backend acceptance. Its full-suite
record includes unrelated Support Wing large-text semantics failures, and live
model inference/external delivery remain untested. These are inherited evidence
and limits, not newly executed checks or proof of the future redesign. Recheck
the current state once at kickoff and run proportionate affected regressions;
retain this goal's final integrated verification requirements.

## Execution sequence — only after go

### 1. Integrate the finished baseline and map data

Read current `git status`, diffs, plan 002, changed tests and the other agents'
completion records. Inspect the relevant source as it now exists. Record the
starting revision and remaining unrelated edits in this plan's evidence section.
Add this plan to `plans/README.md` once concurrent ownership of that index is clear.

Map every overview summary and health finding to its actual current read,
owner, freshness and navigation destination. Establish credential-source limits,
approval/limit semantics, structured versus raw diagnostic results, and supported
usage aggregation. Use local source first; consult primary upstream documentation
when contract interpretation requires it. No live operational checks on entry.

Completion: every R1–R10 item has a current seam and source/contract, and any
necessary unresolved contract is explicitly identified. Keep independent work
moving when a localized decision is needed; never invent backend support.

### 2. Establish overview, hierarchy and ownership presentation

Implement the profile brief, two meaningful Profile groups, current-value rows,
compact scope controls and shared state/status presentation. Build summary loading
with independent failures, explicit freshness, bounded refresh and generation
fences across profile/connection changes. Avoid a new overview-wide network
waterfall or issuing one request per rendered row/build.

Wire known ownership and action-effect labels. Reuse current Studio tokens and
connection status. Retain Server's four destinations and Health's two owners.

Primary seams: `administration_content.dart`, `admin_widgets.dart`,
`administration_repository.dart`, profile workspace state and shared connection
labels. Introduce a focused summary model/controller only where it simplifies
scope, resource lifetime and independent read states.

Completion: R1–R3 exercised with real widgets, independent errors and scope-switch
fixtures; no navigation or supported operation lost.

### 3. Complete inventories and readable details

Implement compact provider inventories/details and explicit service-key addition.
Recompose Skills and tools around capability/skill items with direct setup and
enablement access, retaining Hub and distinct agent-plugin behavior. Refine memory
list/detail and scope-aware empty/read-only states.

Primary seams: `admin_providers_page.dart`, `admin_tool_setup_page.dart`,
`admin_skills_page.dart`, `admin_connectors_page.dart`,
`profile_capabilities_screen.dart`, `admin_memory_page.dart` and their fixtures.

Completion: R5, R6 and R8 acceptance rows pass, including stored-versus-effective
access, external sign-in, row-toggle/disclosure separation and supported-operation
reachability. Secret values do not enter ordinary inventory state.

### 4. Complete editors and search navigation

Add percentage inputs/diagram and explanations to supported behavior editors.
Implement consistent dirty-count/save/effect presentation and field-level conflict
comparison using retained base, draft and latest values. Submit sparse patches
only after deliberate resolution and a fresh comparison; retain uncertainty when
readback does not confirm the result. Move administration Identity into its
full-screen route while retaining existing ownership and save semantics.

Expand search paths/vocabulary, explicit clearing and originating-tab restoration.
Deep-link field results to visible field anchors with transient emphasis and no
unrequested keyboard. Ensure exact input values are not altered by display rounding.

Primary seams: `admin_settings_page.dart`, `admin_defaults_page.dart`,
`profile_editor_sheet.dart` and its administration entry, plus root search.
Inspect non-administration callers before changing shared identity logic.

Completion: R7 and R9a pass, including multi-field conflicts, another remote change
during resolution, scope loss, failed/partial saves, long SOUL and keyboard insets.

### 5. Complete Health recovery and usage comparison

Place observations/findings before utilities within the separate profile/runtime
sections. Connect specific findings to existing owning editors and retain the
return/recheck journey. Show bounded check coverage and outcome summaries with raw
detail disclosure. Distinguish credential availability from inference success.

Replace tall metric repetition with sortable per-model rows, expandable metrics,
readable numbers and honest cost-share bars. Preserve unknown values and all
existing ranges; show estimate/coverage qualifications adjacent to the comparison.

Primary seams: `admin_health_page.dart`, `profile_diagnostics_panel.dart`,
`admin_operations_page.dart`, provider/connector recovery routes and analytics reads.

Completion: R4 and R9b–c pass for untested, partial, stale, failed and successful
observations, absent profile, unavailable runtime identity and missing/zero costs.

### 6. Integrate scheduled tasks, continuity and visual refinement

Use the committed scheduled-task integration baseline above to summarize next run
and latest known outcome, with explicit unavailable/coverage states when necessary.
Keep schedule/run/session ownership, controller leases and uncertainty behavior.
Reduce introductory copy on populated task lists. Preserve scroll/selection context
after edits and refresh only affected summaries where possible. Apply restrained
empty-state copy and reduced-motion-aware emphasis/transitions throughout.

Completion: R10 passes and the whole journey uses the selected Studio language.
Review R1–R9 again in their final integrated context, not only in isolated widgets.

### 7. Verify, document and close

Run meaningful targeted regressions during each phase. At the final integrated
revision, run static analysis, the full host suite and debug build sequentially.
Inspect actual Flutter captures and native interactions using the matrix below.
Fix failures introduced by the redesign; report unrelated baseline failures with
evidence instead of silently claiming clean checks.

Update delivered-behavior docs, design charter/ownership handoff where the approved
presentation changes them, testing entry points and the plan index. Only mark the
goal complete when every required acceptance item and evidence condition is met.

## Acceptance and evidence matrix

All rows start pending. Record implementation/test/capture references in the last
column as work completes; a row passes only when every referenced sub-item passes.

| Requirement | Observable completion criterion | Status / evidence |
| --- | --- | --- |
| R1a–d | Compact profile brief and all seven informative destinations; two groups; scope-safe independent loading with honest unknown/stale states; overview issues only reads | Pending |
| R2a–c | Coherent hierarchy, aligned controls and exception emphasis using shared tokens in light/dark and all accents; growing text and tick-free selection | Pending |
| R3a–d | Three tabs retained; known shared/profile/external sources route to correct owners; effects shown before writes; connection and readiness facts distinct | Pending |
| R4a–d | Profile/runtime findings precede utilities; check coverage/freshness visible; owner-specific edit/return/recheck works; output disclosure and missing-profile access verified | Pending |
| R5a–d | Scannable provider rows and useful details; direct renewal where supported; explicit Add service key; accurate source/removal implications | Pending |
| R6a–c | Capability-oriented inventory/detail with distinct enablement/setup/platform states; skill usage/content/edit/archive/Hub and agent-plugin operations remain reachable | Pending |
| R7a–b | Percent input round-trips correctly; capacity diagram and verified policy/limit/unit explanations aid choices | Pending |
| R7c–d | Dirty count, fixed target, effect labeling, sparse save/readback and deliberate conflict comparison retain drafts across failure/partial/uncertain results | Pending |
| R7e | Dedicated full-screen Identity supports long description/SOUL, keyboard, discard protection, captured ownership and partial-save handling | Pending |
| R8a–c | Memory-first reading/search/detail, concise read-only explanation, source when known and useful empty/settings action; no invented occupancy or writes | Pending |
| R9a | Owner/path search, task vocabulary, clear/back behavior and scroll-to-field emphasis work without surprise keyboard activation | Pending |
| R9b–c | Sortable formatted per-model comparisons and expansion preserve ranges/metrics; cost bars show honest coverage and handle unknown/zero correctly | Pending |
| R10a–b | Scheduled-task integration preserves finished functionality; warm first-use copy, compact populated state, retained context and purposeful reduced-motion-safe updates | Pending |
| R10c | Every changed screen/control meets text-scaling, touch, focus, status semantics, keyboard and row-action criteria | Pending |

Required automated commands, using the repository's configured Flutter SDK:

```bash
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
```

Run appropriate existing `administration_*`, provider-status, tool-setup, Studio
selection/control/layout, app-shell navigation, profile ownership and scheduled-task
regressions plus focused new coverage for summaries, conflict resolution, field
navigation and usage. Select exact files from the finished tree at kickoff.
New tests must establish behavior, asynchronous correctness or real layout risks,
rather than mirror implementation details. Document opt-in skips and their limits.

Required visual/native evidence:

- Actual Flutter light/dark captures of Profile, Server, Health and each changed
  inventory/detail/editor family, with real Roboto and Material icons.
- All five accents represented in shared-control and root checks; every changed
  family at 320 dp/200% text with long names/content. Include a standard phone
  width and a wider layout, empty/error/stale/pending/disabled states, open menus
  and keyboard-open editors. Capture supported partial/uncertain states.
- Native emulator or device checks of keyboard/back/discard behavior, focus and
  screen-reader actions/statuses, 48 dp target edges, separate row disclosure and
  switches, scroll reachability and reduced motion. Fixture-injected native UI
  is valid interaction evidence, not a live-backend certification.
- Exercise new end-to-end journeys: profile switch with late responses;
  shared-access link; finding → owning edit → return → recheck; search → exact
  field; remote conflict resolution; long Identity edit; scheduled run → existing
  conversation. Record source revision, device and evidence paths under ignored
  `build/`, with private content removed.

For scheduled-task integration specifically, verify overview/list observer handoff,
switching between connections with matching task IDs, no duplicate refresh loops,
running/attention rows versus the actual next scheduled run, missing next-run data,
inactive conversations with unknown outcomes, disappeared one-shots and preserved
conversation navigation. Reuse `test/scheduled_tasks_{repository,controller,transport,screens}_test.dart`,
`test/administration_navigation_test.dart` and the committed fixture; extend them
only for changed behavior. The live entry point is
`test/scheduled_tasks_live_test.dart`; native interaction coverage lives in
`integration_test/scheduled_tasks_native_test.dart`.

Live mutations use only an explicitly authorized disposable target after inspecting
driver operations and cleanup. Reuse prior authorization only if it covers the same
target/actions. Never infer that the other agents' server targets are available.
Record live coverage separately; no provider inference or production-account
mutation is necessary to certify this UI redesign.

## Completion and decision boundaries

- The owner released the implementation hold on 2026-09-17. Integrate completed
  concurrent commits while keeping their in-progress checkout intact.
- Default to the direct current target. Compatibility behavior requires explicit
  owner approval under the user's working agreement; do not quietly retain old
  interfaces or implement migration shims as a convenience.
- A missing backend contract requires a concrete report and decision on that
  requirement. Continue independent authorized work; a blocker does not convert
  an accepted requirement into an optional item.
- Missing required native/build/test evidence remains outstanding. Do not mark
  the goal complete merely because code is written or document limitations as
  if that satisfies the required checks. Scope changes must come from the owner.
- This goal authorizes implementation after go, not commit/push, release/signing,
  deployment, real-account changes or unrelated product redesign.

## Evidence record

Preparation only: the accepted review and clarification are captured above; all
acceptance rows remain pending. No implementation, automated app checks, native
runs, live operations or goal activation were performed for this planning request.
Only this plan and its companion design document were created. Leave the shared
plan index and other agents' files unchanged during preparation.

Plan-only follow-up: reviewed the scheduled-task commit `a84abda` and its recorded
acceptance, then updated these two planning documents with the delivered integration
baseline. No goal activation, implementation or app-test execution occurred.
