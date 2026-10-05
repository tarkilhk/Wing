# Scheduled-task edit and ownership contract

Phase 1 fixes D05/D06 in the existing `ScheduledTask`,
`ScheduledTasksRepository`, `ScheduledTasksController` and Studio editor.
The controller remains the single cached task owner; the editor retains an
immutable opening snapshot and sends only fields changed against that snapshot.
No backend changes, compatibility aliases or ownership defaults are introduced.

## Current stock Hermes evidence

Inspected upstream main `21d59f18e7859b99c2a64e6c5e6cfef70365223f`
(2026-10-03 11:22:17 UTC). The inspected cron router and worker are byte-identical
to the previous plan pin `d440c5b59b42d23007ab725f646d3b472670f890`.

- `hermes_cli/web_routers/cron.py`: `_job_owner_profile` treats `profile` as a
  hint, preferring a matching ID/name in that store before searching other stores.
  `_list_cron_jobs_sync` scopes an explicit profile's list. Update, pause, resume,
  trigger and delete resolve the owner through the hint helper.
- `hermes_cli/web_server_cron.py`: `_annotate_cron_job` supplies matching
  `profile` and `profile_name` for returned jobs.
- `hermes_cli/web_models.py`: `CronJobUpdate` exposes updates without an expected
  owner or version condition. Delete returns only `{"ok": true}`.

Before editing, pausing, resuming, triggering or deleting a cached task, the
client reads the captured profile's scoped membership list. Missing, duplicate,
contradictory or unreadable membership rejects the request before dispatch. Job
responses require both explicit, matching owner fields and the requested ID.
Contradictory acknowledgements after dispatch remain uncertain across refresh
and restart until explicit user review; they never trigger an automatic replay.
The review disposition is persisted **before dispatch**. Every unconfirmed
request requires explicit review; a later membership list cannot establish
which store it mutated. Failed pre-dispatch persistence sends no request.
Confirmed acknowledgements and definite preflight/rejection outcomes release
the guard. This conservative policy also survives failed post-dispatch journal
writes; refresh never infers completion from pause/resume/delete state alone.

**Client-only limit:** stock Hermes provides no atomic ownership/version
precondition. A task can move or change between preflight and dispatch. A job
response can reveal an owner contradiction, but delete's acknowledgement cannot
identify the resolved store. These fixes reduce stale-cache hazards and detect
conflicts visible at preflight; they do not guarantee atomic cross-client edits
or prevent every cross-profile mutation during that remaining race window.

## Regression guards

| ID | Property and scope | Guard and legitimate cases |
| --- | --- | --- |
| TASK-EDIT-BASELINE | A refreshed route cannot silently promote newer server values into the opening edit baseline. | Real `AdminTaskRoute` editor regression in `scheduled_tasks_screens_test.dart`: name-only save preserves external prompt, interval, delivery, model and provider. Editor conflict regression preserves the draft and prevents dispatch when its edited field changed. |
| TASK-EDIT-CONFLICT | An edit sends changed fields only; conflicting edited fields and the model/provider pair require review. | Public repository tests cover same-field conflict, paired routing conflict, already-applied desired value, unchanged interval and nested snapshot isolation. Non-overlapping external changes remain valid. |
| TASK-OWNER-PREFLIGHT | Every ID mutation checks fresh membership in the captured profile before dispatch. | Public repository matrix covers update/pause/resume/trigger/delete against missing, unreadable, duplicate and foreign-owner membership; each asserts zero mutations. Canonical-profile/encoded-ID success test exercises all operations. |
| TASK-OWNER-RESPONSE | Missing or contradictory returned ownership cannot become a usable cached task or a confirmed mutation. | Read parser negative/positive fixtures and dispatched-owner tests for update/pause/resume/trigger/create/instantiate. Current stock fixtures include both owner fields. |
| TASK-UNCERTAIN-REVIEW | An unconfirmed dispatched request stays blocked after refresh and restart, including failed later journal writes. | Public controller regressions verify pause/resume/delete recovery from the pre-dispatch durable record despite failed post-dispatch persistence, no replay, no premature reconciliation and explicit acknowledgement. Failed pre-dispatch persistence sends no request; failed preflight clears uncertainty and reports that nothing was sent. |

Static feasibility was evaluated separately for these properties. No standard
Dart/Flutter lint establishes remote membership, event order, concurrent edits,
server response ownership or durable journal reconciliation. An AST/import rule
could require a helper call or forbid a widget reference, but would accept a
stale snapshot, a reordered check or an incorrect reconciliation policy; it
would not establish these properties. Behavioral regression guards therefore
enforce the contract at the existing public seams. Architecture dependency rules
remain supporting structural checks, not proofs of task race safety.

Verification command: the existing quality gate's Flutter tests, including
`test/scheduled_tasks_repository_test.dart`,
`test/scheduled_tasks_controller_test.dart`,
`test/scheduled_tasks_screens_test.dart` and the administration design/health
fixtures. Original D05 route and D06 owner regressions were confirmed red before
production edits; root records the serialized green results and log paths in
the execution ledger. Added matrix cases broaden the same contract; this note
does not claim that every added case received an independent historical red run.
