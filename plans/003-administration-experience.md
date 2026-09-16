# Plan 003: Complete the administration experience redesign

Status: DONE — accepted redesign implemented and verified on the isolated branch.

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

## Execution sequence

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
`admin_identity_page.dart` and its administration entry, plus root search.
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

All acceptance rows are complete. References below identify implementation and
verification; the execution record distinguishes host, rendered and native evidence.

| Requirement | Observable completion criterion | Status / evidence |
| --- | --- | --- |
| R1a–d | Compact profile brief and all seven informative destinations; two groups; scope-safe independent loading with honest unknown/stale states; overview issues only reads | Pass — `admin_profile_overview.dart`, `administration_overview.dart`; overview/comparison/navigation tests; light/dark/root captures. |
| R2a–c | Coherent hierarchy, aligned controls and exception emphasis using shared tokens in light/dark and all accents; growing text and tick-free selection | Pass — `admin_widgets.dart`, `studio_select.dart`; all-accent navigation and Studio control/selection tests; 320 dp/200% and wide captures. |
| R3a–d | Three tabs retained; known shared/profile/external sources route to correct owners; effects shown before writes; connection and readiness facts distinct | Pass — provider/defaults/detail routes and captured repositories; provider-status, ownership and navigation tests; native canonical shared-account link. |
| R4a–d | Profile/runtime findings precede utilities; check coverage/freshness visible; owner-specific edit/return/recheck works; output disclosure and missing-profile access verified | Pass — `admin_health_page.dart`, `profile_diagnostics_panel.dart`, `admin_operations_page.dart`; diagnostics/recovery tests and retained Health → search → editor → recheck test; Health captures. |
| R5a–d | Scannable provider rows and useful details; direct renewal where supported; explicit Add service key; accurate source/removal implications | Pass — `admin_providers_page.dart`; provider status/renewal tests and explicit service-key journey; inventory/detail/catalog captures; native shared-account navigation. |
| R6a–c | Capability-oriented inventory/detail with distinct enablement/setup/platform states; skill usage/content/edit/archive/Hub and agent-plugin operations remain reachable | Pass — direct `ProfileCapabilitiesScreen` entry with setup/library/Hub/plugin callbacks; capability/tool/skill regressions; native separate disclosure, toggle and setup actions. |
| R7a–b | Percent input round-trips correctly; capacity diagram and verified policy/limit/unit explanations aid choices | Pass — `admin_settings_page.dart`; exact-decimal, invalid-exponent and percentage tests; upstream unit/special-value inspection; compression captures. |
| R7c–d | Dirty count, fixed target, effect labeling, sparse save/readback and deliberate conflict comparison retain drafts across failure/partial/uncertain results | Pass — sparse-save/ownership tests, repeated remote-conflict test, retained draft/unconfirmed captures and native conflict resolution; failures reveal their explanation. |
| R7e | Dedicated full-screen Identity supports long description/SOUL, keyboard, discard protection, captured ownership and partial-save handling | Pass — `admin_identity_page.dart`; retained profile-editor regressions, long/partial captures, native keyboard/back/discard/save journey. |
| R8a–c | Memory-first reading/search/detail, concise read-only explanation, source when known and useful empty/settings action; no invented occupancy or writes | Pass — `admin_memory_page.dart`; read-only/search/empty/failure regressions; list/detail captures, source separately visible below excerpts. |
| R9a | Owner/path search, task vocabulary, clear/back behavior and scroll-to-field emphasis work without surprise keyboard activation | Pass — scoped search paths, exact-field keys and reduced-motion-aware reveal; editor/navigation tests including keyboard absence and originating Health tab restoration. |
| R9b–c | Sortable formatted per-model comparisons and expansion preserve ranges/metrics; cost bars show honest coverage and handle unknown/zero correctly | Pass — `AdminUsagePage`; formatted expansion/sort/range, unknown/invalid/zero-total tests; light/dark/large-text/wide usage captures. |
| R10a–b | Scheduled-task integration preserves finished functionality; warm first-use copy, compact populated state, retained context and purposeful reduced-motion-safe updates | Pass — leased scheduled-task controller in overview, latest listed-run coverage, next-run selection and stale timestamp; full scheduling regressions, overview handoff test, retained tab state and reduced-motion checks. |
| R10c | Every changed screen/control meets text-scaling, touch, focus, status semantics, keyboard and row-action criteria | Pass — growing titles/selects/field labels, keyboard-safe footer; full Studio/layout tests and rendered matrix; native keyboard/focus/semantics tap plus independently exposed 48 × 48 dp switch and row actions. |

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
- The owner authorized an isolated branch and integration of concurrent commits.
  Local branch checkpoints are part of that work. Release/signing, deployment,
  real-account changes and unrelated product redesign remain outside this goal.

## Evidence record

Preparation only: the accepted review and clarification are captured above; all
acceptance rows remain pending. No implementation, automated app checks, native
runs, live operations or goal activation were performed for this planning request.
Only this plan and its companion design document were created. Leave the shared
plan index and other agents' files unchanged during preparation.

Plan-only follow-up: reviewed the scheduled-task commit `a84abda` and its recorded
acceptance, then updated these two planning documents with the delivered integration
baseline. No goal activation, implementation or app-test execution occurred.

### Execution record, 17 September 2026

Implementation started at `28b7f61` in the isolated worktree named above. The busy
original main checkout was left intact. Checkpoints `5b57e02` and `79bd15c` establish
the redesign. Main was integrated through `818ecbe` in merge `d7922e1`, including
voice input/output, final preview greeting and microphone placement, project
selection/header refinements, and Support Wing fixes. The two feature agents'
completion records report their phone installations complete. No agent in this
thread tree was available for direct cross-thread messaging; synchronization used
committed main state and their completion records.

The greeting/layout conflict was resolved by retaining Studio's single gutter and
phone/profile ownership copy together with the exact approved greeting. Analysis
and all 18 voice/project regression tests passed after that merge.

Execution-limit help was checked against local upstream source at
`af4a3eba0a3674633050bf1c41df45f8ed6f0858`: `agent/agent_init.py` normalizes a
nonpositive run budget to no budget; `tools/delegate_tool_config.py` sets a positive
child timeout floor of 30 seconds, disables it at zero, and floors spawn depth at
one. These describe the exposed settings rather than adding legacy behavior.

Render entry points: `test/administration_design_test.dart` (11 families × light,
dark, 320 dp/200%, 840 dp; pending/unconfirmed compression and partial Identity),
`test/administration_navigation_test.dart` (all five accents in both themes, roots,
missing profile and keyboard), and the integrated `test/project_picker_design_test.dart`.
The combined final capture run passed 70 tests. Actual images are under ignored
`build/administration-preview/` and `build/project-picker-review/`.

Render review corrected clipped selected values/page titles, large-text labels,
Save-caption wrapping, excess provider/voice gutters, cost-bar semantics, and save
notices hidden above long drafts. Targeted navigation/Studio regressions passed 40
tests. Final analysis, host-suite, normal debug-build and native results follow.

### Final verification

- Static analysis: `flutter analyze --no-pub --fatal-infos` — no issues.
- Full host suite: **2,000 passed, 11 opt-in live tests skipped**. Earlier failures
  were old route-label/scroll expectations; corrected tests retain their behavior
  assertions. The final full-suite log is `build/administration-native/host-tests.log`.
- Final presentation/observation regression and capture pass: **71 passed**;
  includes the final separate memory-source line and task stale-check timestamp.
- Normal development APK: `flutter build apk --debug --no-pub` — passed. Preserved
  at `build/administration-native/wing-administration-debug.apk` before native-test
  builds. SHA-256: `46bae6bfd2a0541002a5ea7f58075c3c2210b3317d20cc1e5ee610135bda0976`.
  Existing Kotlin-plugin toolchain warnings did not prevent the build.
- Native: **3 passed** in `integration_test/administration_native_test.dart` on
  disposable `emulator-5558`, Android API 36, 320 × 640 dp. Its independent AVD is
  under `/tmp/wing-administration-avd`; no user phone or other agent's emulator
  profile was used. The screenshot and Android accessibility tree are
  `build/administration-native/android-capability-actions.{png,xml}`.
- Native checks exercised an accessibility action into an editor, real keyboard,
  a remote conflict and explicit resolution, clean save then dirty discard, a long
  Identity draft/back/cancel/save, canonical shared ownership at 200% text, and
  separate tool disclosure/toggle/setup. The target-edge tap succeeded. Android
  exposes the switch as checkable/unchecked with bounds `[256,424][304,472]`,
  separate from the expandable row and Setup and providers button. Reduced-motion
  rendering and keyboard focus were also exercised.
- Actual final Flutter renders were inspected for roots, all changed families,
  partial/unconfirmed/pending editors, narrow and wide layouts, and incoming
  voice/project UI. All five accents are represented in root/shared-control checks.
- `git diff --check` — clean. Main changes through `818ecbe` are integrated.

The opt-in live drivers require an explicitly supplied disposable backend and were
not activated. No real provider inference, account changes, deployment, release or
phone installation was performed for this redesign. Native fixture acceptance and
Android accessibility-tree inspection do not certify every screen-reader product
or a live backend. These are the agreed evidence boundaries, not omitted UI work.
