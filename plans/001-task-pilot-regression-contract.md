# Scheduled-task owner pilot

The original blueprint integration inspected official upstream main at
`7533bd2756b9526b52f527f737420a19e57331d7`; its catalog is represented by the
accepted V03 artifact. Conflict reconciliation refreshed official upstream main
at `8b66a51036c1e20920a17cdd049fdf55c968d683` before implementation. Inspected
sources are `hermes_cli/web_routers/cron.py`, `hermes_cli/web_models.py` and
`cron/jobs.py`, with exact source hashes and retrieval provenance retained in
private acceptance evidence. No stock mutation was performed. This is a
client-only implementation; no backend changes or compatibility interfaces are
introduced.

## Owners and call obligations

- `ScheduledTask` / `TaskTemplateField` / `TaskTemplate` own typed stock records,
  field defaults/required/strict/suggested options, supported-field facts, and
  status/ranking/detail projections. The optional-field unit case describes
  generic stock `BlueprintSlot` semantics, not an advertised catalog invention.
- `TaskScheduleDraft` owns schedule decomposition, exact untouched expressions,
  encoding and validation against a supplied clock. An expired one-shot remains
  editable when its schedule is untouched; changing it requires a future time.
- `TaskEditIntent` captures the immutable opening baseline and user changes.
  Its sole `resolve(current)` determines sparse updates and conflicts. A model
  change reviews provider and `base_url`; a dispatched model/provider update is
  a pair. Existing custom endpoints stay managed on the server. A fresh
  script-only task also conflicts with dirty instructions or routing even when
  their stored values are unchanged: those edits cannot affect script-only
  execution and require an explicit discard.
- `TaskEditReview` observes that sparse intent without changing it. Each
  conflicting field requires an explicit Keep mine or Use server decision;
  model/provider/endpoint conflicts are one routing decision. A current custom
  endpoint cannot be overwritten by the task model picker. Script-only
  instructions/routing expose an owner-provided reason and disable Keep mine;
  Use server discards only that decided field. Incomplete or unsupported choices
  keep the entire opening baseline and draft. Reconciliation
  establishes the reviewed observation as a baseline, retaining only original
  edits the user kept. It does not turn untouched server fields into edits.
- `ScheduledTasksRepository.update(intent)` resolves once, immediately after
  fresh scoped membership and before PUT. Session/cache refresh never substitutes
  a new baseline. The stock read/write pair is non-atomic: stock has no client
  revision precondition and can change after that read. No client guard claims
  otherwise. Existing authoritative-response and durable-uncertainty checks stay.
- `ScheduledTaskEditSession` owns one route's inputs, baseline, catalogs and
  independent load generations, destination eligibility/minimum selection,
  template values, atomic model selection, validation and save outcome. Its
  immutable state is the view interface. Views retain text/focus/scroll, picker
  staging, localized formatting and navigation. Catalog errors are independent;
  current/unavailable choices survive discovery failures.
  `reviewConflicts()` reads fresh membership in the captured profile and issues
  an opaque immutable review ticket bound to this session and draft revision.
  `applyReview(ticket, decisions)` only changes local intent; `cancelReview`
  keeps the exact inputs and opening baseline. Later edits, another review,
  saving and disposal retire older tickets. The next Save still performs the
  repository's fresh membership/conflict check; a second remote change refuses
  that write and requires another explicit review.
- `ScheduledTasksController` remains the sole task-cache/action/journal owner.
  It captures inputs before journaling and owns action eligibility, confirmation
  facts and uncertainty review. A route-local owner does not cancel its request.
  Registry leases retain already mutating operations through route closure.
  Rows, request guards, journal records and status fields have private backing
  state. Public getters are observations only: row replacements are immutable,
  busy/journal collections are stable immutable snapshots, and recovered journal
  descendants are frozen. Callers cannot clear a guard, inject rows, change
  status or rewrite a review disposition through a retained alias. Cache changes
  require real reads or admitted commands; uncertainty clears through explicit
  acknowledgement. Existing public read names remain, without external setters.
- `ScheduledTasksObservation` owns list refresh eligibility and timer cleanup.
  `ScheduledTaskDetailSession` owns captured-task history paging/generations,
  stale-row retention, conversation identity and opening lifetime. Both receive
  visibility/resume facts from views and read the existing retained cache.

A reducer-only alternative would leave callers responsible for catalog loading,
scope capture, scheduling, disposal and save classification. The selected route
owner hides those obligations without another repository or journal. List/detail
observations have distinct read lifetimes; they do not duplicate edit state.

## Behavior verification

Public seams under test are the repository, route edit/history owners, retained
controller and actual routed widgets. Controlled tests cover stale/conflicting
edits, coupled model/custom-endpoint changes, exact untouched schedules, clock
validation, stock/default/strict/suggested/optional slot semantics, unavailable
destinations, held/failed catalog generations, bounded history, polling visibility,
dispose during dispatch, uncertain-save retention and explicit review. Existing
Studio route and layout tests remain required.

## Explicit conflict recovery and dirty dismissal

The initial public regression pushed the real leased task editor, changed its
name, observed another client's name and unedited prompt, then attempted Save.
It proved zero server mutations, retained dirty input, the live route and the
conflict notice before failing because Review changes was absent. The preserved
original acceptance snapshot distinguishes that real recovery failure from
test setup errors.

The recovered flow presents only conflicting fields in a scrollable Studio
sheet. Applying decisions is local; Save changes remains the write action.
Cancelling the sheet preserves the baseline and raw dirty text. A server choice
adopts only the corresponding field, preserving unrelated dirty inputs. Newly
observed untouched fields are adopted during explicit reconciliation so they
cannot become accidental writes. A review is not a revision token or permission
to overwrite subsequent remote changes.

The refreshed stock router exposes GET list/detail and PUT `{updates: dict}`.
Its detail lookup can resolve the actual owner despite a profile hint; review
uses a fresh scoped list instead. `_update_cron_job_sync` reads the existing job,
normalizes sparse updates and calls `update_job`. Neither `CronJobUpdate` nor
`update_job` accepts a client revision precondition. Concurrent changes between
the client preflight and stock write remain outside this client's atomicity
claim.

Public owner tests cover cancel/no rebase, Keep mine and Use server with exact
sparse writes, complete decisions, coupled custom routing, remote convergence,
another remote change, foreign/older tickets, held reads superseded by editing
or disposal, and offline/removed/wrong-profile membership. The pure intent probe
independently covers reconciliation and coupled route intent. Pushed widget
tests cover recovery to one scoped write, cancellation, field-controller updates,
320 dp/light/dark/200% action reachability, and dirty Back → Stay / Discard with
zero writes. The existing dirty-pop production guard is preserved.

Recurrence ledger: `ARCH_TASK_VIEW_PROTOCOL` continues to forbid canonical
repository/administration invocation and capture in the four task views,
including the new review presentation. Typed decisions cross the existing owner
seam; the view never holds a task observation or constructs an update map. A
static rule cannot establish whether a remotely observed value changed during
a dialog, whether a ticket belongs to the current draft, or whether cancellation
preserved inputs. The named public behavioral regressions enforce those
properties; method-name checks or mandatory dialog source strings would not.
A preserved independent counterexample edited instructions/model alongside a
name conflict while stock changed the same task to `no_agent: true` with a
script. The old review adopted script-only execution without deciding those
edits; the next Save omitted them and falsely confirmed an empty update. Public
owner and pure-intent regressions now require explicit execution-field decisions,
refuse unsupported Keep mine, preserve independent kept edits, and repeat fresh
mode checks after review. The stock mode transition is supported by the pinned
`update_job` merged-field validation; this client does not claim a revision token.

The controller observation-boundary regressions separately exercise real row
refresh, a held request, a lost acknowledgement, and recovered journal JSON.
The original four cases demonstrated mutation of row, busy, journal and child
collection aliases without an exception. Successors require rejection while the
owned state/guard remains intact, then verify that genuine command settlement or
explicit review still changes the controller while older snapshots remain
stable. The canonical caller audit found only reads outside this owner; it is
bounded authored-source evidence, not whole-program dynamic reachability.

The independent rule and its unchanged invalid/valid/input-error fixtures stay
mandatory, alongside ordinary SDK analysis. No temporal linter claim or new
baseline is introduced by this batch.

```sh
dart run tools/architecture/tests/task_edit_intent_test.dart
flutter test --no-pub test/scheduled_tasks_edit_session_test.dart test/scheduled_tasks_detail_session_test.dart test/scheduled_tasks_repository_test.dart test/scheduled_tasks_controller_test.dart test/scheduled_tasks_screens_test.dart test/scheduled_tasks_blueprint_contract_test.dart
```

## Independent structural guard

`ARCH_TASK_VIEW_PROTOCOL` forbids scheduled-task view/presentation libraries
from invoking or capturing operations declared by canonical
`ScheduledTasksRepository` or `ProfileAdministration`. Remedy: send typed input
through the application owner. Direct calls, aliases, prefixes, exports,
typedefs, cascades, method tearoffs, inherited methods and definition/consumer
parts are checked with resolved declaration provenance. Unrelated symbols,
including SDK methods with the same name, and application-owned requests pass.
Candidate conditional-import branches and unresolved dynamic calls fail with
input exit 2 instead of pretending the selected environment proves provenance.

```sh
dart run tools/architecture/rules/task_view_protocol.dart --json
dart run tools/architecture/tests/task_view_protocol_test.dart
flutter test --no-pub test/scheduled_tasks_protocol_guard_test.dart test/scheduled_tasks_intent_guard_test.dart
```

The independent 16-case proof invokes the real CLI for invalid, valid and
unverifiable inputs. Its host wrapper runs in the mandatory complete host-test
gate. The aggregate runner may share its immutable parse snapshot; rule logic
remains independent. No suppression or baseline is needed. Always check the full
four task view libraries in CI. For local changes, include their affected parts
and import/export closure; changing/deleting an owner or manifest requires full
checking. This rule proves direct protocol-access ownership only. It cannot
establish all business-policy ownership, resource ordering, races or save outcomes;
those require behavioral tests and semantic review.

Feedback contract for the current 269-source checkout: target at most 50 ms for
the clean rule on an already parsed snapshot and at most 10 seconds for its cold
JIT standalone command. Measure both when changing scope/implementation; parser
and SDK startup are separate costs. Archive timings in ignored
`build/architecture-program/` per `docs/PERFORMANCE.md`; noisy timings never alter
the deterministic correctness result. Candidate cases legitimately pay resolved
analysis cost, measured separately in the independent fixture proof.

## Picker bounds and current stock schedule projection

The route owner supplies immutable date-picker bounds and a clamped initial day.
The view commits only after both date and time selections complete. Cancelling
at either step leaves the exact opening expression and dirty state unchanged,
including expired one-shots and valid dates beyond the picker's ten-year window.
The picker window constrains that control, not the accepted stored schedule.
Actual picker widget tests cover both cancellation steps and explicit selections;
static syntax checks cannot prove bounds for arbitrary stored instants/clocks.

Fixture projection and ISO comparison were rechecked against official upstream
`3251a180f01ad21ae059862997307bf75f3e3f0a`: `cron/jobs.py:784` parses schedule
strings; `_apply_schedule_update` at 2079 updates the schedule/display; the
HTTP update at `hermes_cli/web_routers/cron.py:599` delegates to this stock path.
The independent stock projection artifact is
`tools/contracts/hermes_task_schedule_projection.json`, with full source/parser
hashes, seven response cases and a fixed injected UTC clock. Its generation used
selected parser functions without module initialization or backend I/O and a
validator limited to independently known-valid cron cases. It establishes DTO
projection, not general croniter validation, firing or blueprint filling.

The fixture now projects the four canonical UI forms explicitly: cron,
`every Nm`, `in Nm` and aware ISO timestamps. Unsupported/malformed fixture
inputs fail rather than being manufactured as cron records. Blueprint fixture
jobs remain synthetic; the separate accepted blueprint contract covers their
advertised schema/slots, not full schedule filling. The actual Dart fixture's
create/update rows are exported by
`test/scheduled_tasks_schedule_projection_test.dart` to the independent
`STOCK_TASK_SCHEDULE_PROJECTION` CLI. Its offline valid/invalid/input-error
proofs run through mandatory `tools/qa` discovery; actual exports run through
the mandatory complete host suite.

```sh
python3 tools/architecture/rules/stock_task_schedule_projection.py --input actual.json
python3 -m unittest tools.qa.test_task_schedule_projection -v
flutter test --no-pub test/scheduled_tasks_schedule_projection_test.dart test/scheduled_tasks_repository_test.dart test/scheduled_tasks_edit_session_test.dart test/scheduled_tasks_screens_test.dart
```

The projection rule checks all seven cases for both POST and PUT, accepts
unrelated job fields, rejects a wrong kind/value/display with exit 1 and reports
malformed input/artifact with exit 2. It is deterministic and offline; changing
this artifact requires the complete case set, not changed-file sampling. Its
local feedback budget is 100 ms per standalone Python process on the recorded
seven-case input; archive measured startup/runtime under ignored tooling output.
No code-pattern regex is offered as proof of fixture semantics.

Stock formats an aware UTC one-shot as `+00:00`, whereas the picker sends `Z`.
`ScheduledTask.normalizeEdit` compares supported aware ISO instants at full
microsecond precision without replacing stored or outgoing text. A converged
external time or an explicit reselect of the same instant produces no PUT;
a distinct remote microsecond still conflicts. Other schedule expressions keep
exact expression semantics; naive timestamps need profile-timezone authority
and are not assigned an invented UTC meaning. Public repository regressions,
actual stock-style readback and the independent pure intent probe enforce this
semantic property. The pre-fix pure public probe failed at UTC convergence;
this is behavioral red evidence, not a static-linter CLI exit claim.
