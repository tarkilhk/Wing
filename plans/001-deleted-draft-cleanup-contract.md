# D04: durable deleted-chat draft cleanup

## Authority and stock contract

`ProfileWorkspaceController` remains the action/navigation/cache owner.
`DeletedDraftCleanupStore` stores immutable host/profile/session receipts and
serializes writes; it dispatches no backend commands and owns no chat cache.
`AttachmentDraftService` alone grants a validated managed-file cleanup capability.
The browser projects `blocksSession`, including uncertain prepared quarantine.
Production ownership requires the existing `main.dart` controller factory and
`ProfileWorkspaceRegistry.putIfAbsent(identity)`: one workspace controller per
verified identity owns action dispatch. The journal serializes persistence but
does not claim to arbitrate multiple independently constructed action controllers
or backend clients atomically. No production duplicate-owner path was found.

Inspected unmodified official Hermes main:
`b412ee9206e977526555129b185253ed35e2bc0b`. Source references are
`hermes_cli/web_routers/sessions.py` (detail and deletion),
`hermes_cli/web_server_sessions.py`, and `hermes_cli/web_server_cron.py`
(profile-resolution error branch). Detail is a **direct row**, including profile;
there is no `session` wrapper. Exact detail `404 {"detail":"Session not found"}`
can represent absence only after valid captured profile membership is established
again. Profile missing, corrupted storage `503`, authentication errors, prefix
matches returning another ID, malformed rows and generic 404 are unavailable.
Archived sessions still have detail rows. Filtered/paginated session lists do not
prove absence. DELETE acknowledges both actual removal and already-absent IDs.

`ProfileGateway.verifyDeletedSession` is read-only and returns
`SessionPresence.absent/present/unavailable`. It validates exact ID/profile and
fresh membership before and after the detail observation. This is observational
and non-atomic; stock has no revision/CAS endpoint. Recovery never replays DELETE.

## Receipt lifecycle

| Phase | Publication/recovery | Destructive local authority |
| --- | --- | --- |
| prepared | Deletion uncertainty; quarantine blocks opening, saved-draft transfer, pending/outbox resume and mutations. | None until ACK or fresh owned exact absence. |
| acknowledged | Immediately hidden from browser/navigation; restart seeds tombstone before reading cache. | Retry local cleanup only. |
| completed | Minimal durable tombstone retained; old snapshots cannot restore chat. | Cleanup already complete; no repeated backend request. |

Passive readers remain available for rendering. `_commandOwner` separately
refuses commands for closed, transiently quarantined or durably blocked chats;
mutating flows recheck after held inputs and immediately before physical dispatch.
Unsent retained work remains available after an explicit Keep decision.

Prepare persistence succeeds **before** any server dispatch. Failure keeps work
and sends no server operation. Captured files contain only immutable local metadata,
never composer text, queued message text, credentials or upload references.

A received deletion ACK publishes removal before any local await. Captured earlier
draft writes settle before the final stored-draft metadata read and clear. Draft
persistence checks acknowledged memory/durable authority both at admission and
when an ordered save executes. A late command finalizer cannot recreate work
after ACK cleanup; prepared or closed non-ACK work can still be retained. Cleanup
journals complete file metadata, validates the whole batch before clearing work,
clears the local record, performs strict idempotent managed-file removal, then
persists a completed tombstone. Real cleanup and journal I/O failures remain pending.
A failed post-ACK journal write retains the earlier prepared durable record while
the live controller keeps acknowledged removal published. On restart it is
conservatively quarantined until a fresh owned absence can be observed. Disposal
does not cancel an already-dispatched operation's receipt/cleanup completion. A
closed owner refuses new actions and rechecks its lifetime after held preparation,
before starting any server operation; its prepared work stays quarantined.

Prepared present/unavailable observations remain inert and retain local work.
The controller publishes immutable `DeletedDraftCleanupPresentation` through a
listenable, including owner-supplied summary, entries, progress, errors and action
callbacks. Presentation inspects no receipt phase or presence to infer authority.
Check chat performs the read-only observation; confirmed absence permits existing
local-only cleanup. A freshly present prepared receipt offers explicit Keep chat,
which verifies exact presence again and durably retires **that captured prepared
receipt only** before unblocking preserved work. Failed retirement keeps quarantine
and work. Stale callbacks cannot retire later receipts; closing during a held
verification keeps the decision inert. No choice silently opens a chat, resumes a
queue, cleans files, repeats deletion or retires acknowledged/completed tombstones.

Recovery publication compares the previous publication's receipt identities and
passive title, presence, error, busy and confirmed-deletion facts before sorting
and constructing new entries/actions. Unrelated stream updates do not replace or
notify an unchanged recovery presentation. Replacing an immutable receipt must
publish new captured callbacks even when its displayed facts are identical. This
bookkeeping is not another request, journal or chat-cache owner; scanning the
bounded receipt snapshot remains necessary. Ordinary composer edits do not call
the workspace publication path and are not claimed as this finding's trigger.

The public streaming regression first verifies actual streamed text and workspace
notifications, then checks recovery notifications/identity. Original production
publishes six unnecessary recovery updates during that controlled live response.
A separate same-display receipt replacement case verifies old callbacks are inert
and the new callback finishes only local cleanup. Static analysis cannot establish
equivalent runtime facts, notifier delivery or captured receipt replacement
freshness; these behavioral regressions guard that property without a source-text
assertion or a blanket notifier ban.

## Managed file authority

Persisted paths are untrusted. The strict cleanup capability uses the attachment
service's existing trusted directory provider (app support `attachment_drafts`).
All paths must be bounded absolute direct children, have matching actual generated
`draft-<microseconds>-<sequence>.(bin|jpg|png)` identity and bounded byte length.
The trusted root is canonicalized; non-regular files, symlinks, contradictory size,
escaping/traversing paths and changed roots fail closed. Whole-batch validation
precedes draft clearing. Missing legitimate managed files are idempotent success.
If the whole managed directory is absent, its leaf is bound to the existing
canonical trusted parent and all direct-child metadata is still validated. Strict
cleanup rechecks that parent/absence and completes without recreating the cache.
Missing or changed trusted parents remain pending. Removal rechecks canonical
root/leaf and propagates I/O errors. General accepted-
upload housekeeping retains its existing separate semantics.

Dart lacks directory-handle-relative `openat`/`unlinkat`. These checks reject
observed symlinks and bind cleanup to the app-private managed directory; they do
not claim atomic protection against another writer replacing a path between the
last check and deletion. Invalid records preserve their receipt and remaining
local work rather than deleting another path or treating cleanup as complete.

## Admission and corruption

Each connection ID + verified identity has at most 1,024 receipts, 1 MiB total
encoded metadata, and 256 KiB per record. Empty completed tombstones consume only
a small record; the budget contains no attachment payload. Admission rejects
before a new deletion dispatch rather than evicting old or uncertain records.
ACK metadata growth beyond a limit keeps prior receipt/work and reports pending
cleanup. This finite local budget is an explicit product limitation: after enough
retained deletions new ones are refused until a separately designed safe journal
compaction policy exists. There is no silent tombstone eviction or fallback reader.
Unknown/malformed journal records fail closed instead of authorizing cleanup.

## Verification and regression guard

`test/chat_browser_mutations_test.dart` covers public restart with a new preference
object, deliberately stale reading cache, failed prepare/ACK/completion writes,
held ACK I/O, held older draft writes, file-removal failure/retry, disposal during
in-flight ACK, ACK before a held catalog finalizer (no cleared draft recreation),
disposal during held prepare without dispatch, present/unavailable
quarantine, durable explicit Keep retirement, failed/held retirement, fresh absence
or unavailable Keep refusal, closed held verification, exact-receipt stale action
callbacks, known ACK refusing Keep, kept outboxes, external paths, missing managed directory,
symlinks, and admission without eviction or dispatch. The original controller
fails the real restart case: cached deleted chat is restored before initialization.
Private original RED: `build/architecture-program/deleted-draft-restart-original-red.log`.

`ARCH_DELETED_DRAFT_CLEANUP_BOUNDARY` is an independent structural property:
inside `DeletedDraftCleanupStore` and the controller's `_cleanupDeletedDraft`,
forbid canonical direct `dart:io` File/Directory/Link/FileSystemEntity references
and delete/deleteSync calls, plus the attachment owner's general
`removeCachedFile/removeAll`. Use its strict validated batch capability. Candidate
AST names and aliases only select resolution work; diagnostics require canonical
resolved API identity. Actual library/part provenance governs scope. Nearby
unrelated names and ordinary upload behavior are valid. Conditional candidate
provenance and unresolved dynamic calls fail with input status 2 rather than
claiming verification. Full production check is required in CI; changed-only
checking cannot omit renamed parts or changed exporters/declaration aliases.

Independent commands:

```
dart run tools/architecture/tests/deleted_draft_cleanup_boundary_test.dart
dart run tools/architecture/rules/deleted_draft_cleanup_boundary.dart --json
dart compile exe tools/architecture/rules/deleted_draft_cleanup_boundary.dart -o build/architecture-program/deleted-draft-cleanup-boundary
dart run tools/architecture/tests/deleted_draft_cleanup_boundary_test.dart --compiled build/architecture-program/deleted-draft-cleanup-boundary --sdk <dart-sdk-root>
flutter test test/chat_browser_mutations_test.dart test/deleted_draft_cleanup_boundary_guard_test.dart
```

The normal host test wrapper discovers the standalone fixture/CLI proof. Correctness
exits are 0 valid, 1 property violation, 2 malformed/unverifiable input. No baseline
or suppression. Runtime evidence is recorded after the actual proof on the stated
checkout/SDK; timings do not change correctness exit status.

This narrow structural property does not inspect arbitrary callback/helper
implementations or establish all possible filesystem effects. Static analysis
cannot establish server ACK occurrence, durable storage outcome,
crash point, I/O ordering, cache substitution or filesystem races. Controlled held/
failed I/O, real preference restart and HTTP ownership tests cover those behaviors.
The boundary guard supports these tests and does not replace them.

`test/profile_prompt_dispatch_closure_test.dart` separately holds the actual
pending-journal write and closes the workspace before regeneration or a saved
message edit can dispatch. It verifies zero physical prompt requests, unchanged
server history, restored local transcript/status/streaming, retained composer and
queue contents, and both initially paused/unpaused durable queue state. The
original marker-before-final-authority implementation fails with changed local
transcript despite zero requests. Marking dispatch follows the final authority
check immediately before gateway invocation; definite no-dispatch restores the
original state, while actually dispatched uncertainty retains its existing policy.
Static analysis cannot establish when a held preference write or synchronous
publication listener retires the owner, or whether that controlled interleaving
produced a physical request. The public behavioral guard owns this property;
lexical marker adjacency alone would not prove its execution outcome.

Local feedback budgets for this independent guard, established on the current
287-file input with the existing Dart SDK: clean source CLI 10 seconds, compiled
clean CLI 350 milliseconds, and compiled property check (excluding shared parse)
10 milliseconds. Benchmark cold startup and three warm runs, compiling the exact
source once. Retain host/SDK/input hashes and actual observations under ignored
`build/architecture-program/`, as required by `docs/PERFORMANCE.md`. These quiet
local budgets are observational; noisy CI correctness is determined by findings,
not elapsed time. Candidate provenance resolution has a separate fixture workload
and cannot be represented by the clean no-candidate budget.
