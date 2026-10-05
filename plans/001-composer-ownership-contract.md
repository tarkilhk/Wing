# Composer and outbox ownership

The conversation's `ComposerSession` owns unsent text, its revision, attachment
membership, ordered local persistence, queued instructions, editing, pause and
delivery uncertainty. `ProfileChat` owns runtime/transcript facts and references
this owner; it has no forwarding draft or queue fields. The workspace owns chat
membership, captured command authority, quarantine and acknowledged tombstones.

`ComposerDraftStore` remains the only draft persistence adapter. Its existing
`composer_work_v2` keys, record fields and ordered per-record writes remain
unchanged. `AttachmentDraftService` remains the staged-file, sanitation and
upload adapter. Mutable attachment records stay inside the composer/adapter
implementation. Observations copy their values; immutable outer lists alone do
not establish immutable observations. Queue identities are opaque and stable
across value replacement, uncertainty and rollback.

## Interface choice

A single callback that sends a draft would hide the point at which the runtime
must claim the transcript before events arrive, or require callbacks for each
runtime mutation. Instead, a composer-issued submission ticket captures the
exact work/revision. The workspace performs runtime admission and dispatch and
settles that ticket. Neither side receives the other's mutable state.

| Transition | Fact owner and obligation |
| --- | --- |
| Type / queue / edit queued instruction | Composer increments revision, reserves durable capture before publication and rolls back only facts still owned by the failed command. |
| Prepare or share files | Composer owns captured membership/generation and discarded-result cleanup; attachment adapter owns resource processing. |
| Admit submission | Composer captures outgoing work and persists it before runtime journal/dispatch. Fresh typing remains separate. |
| Dispatch | Workspace captures runtime and checks its real command authority adjacent to RPC. Runtime alone owns transcript/status/event generations. |
| Settle submission | Composer distinguishes definite refusal, possible dispatch and acknowledgement. Uncertain work is paused and never automatically resent. |
| Accept steering | Runtime owns receipt/transcript; composer consumes only the captured draft revision, including when text changed away and back. |
| Terminal / reconnect | Runtime publishes its availability; composer decides whether its queue can drain. Reading snapshots grant no execution or decision authority. |
| Replace runtime / recover saved work | Workspace verifies target identity; composer reserves both owners and joins both admitted tails before the existing ordered store move. The admitted move is itself a tail that acknowledged cleanup joins. An owner never changes its captured key. Failure retains recoverable work; a completed move retires the old writer even if the destination closed before publication. An unmaterialized source has a captured workspace command reservation during its store move. |
| Prepare deletion | Workspace's existing durable receipt/quarantine fences commands and keeps local work. No destructive composer cleanup occurs. |
| Acknowledge deletion | Workspace publishes tombstone first; composer retires new admission and late writes. Cleanup joins its admitted write tail and captured file receipts, never repeats DELETE. |
| Close / retire | Route unmount does not dispose conversation work. Workspace retirement revokes commands/preparation; already admitted persistence settles conservatively. |

## Stock contract

Read-only inspection of official unmodified Hermes main
`1298c8e74baa73e1a2b90124228d017261ac6bc4` covers
`tui_gateway/methods_prompt.py` (`prompt.submit`, session/text input) and
`tui_gateway/methods_session.py` (`session.steer`, queued/rejected receipt).
This extraction preserves the current client protocol; it adds no endpoint,
server journal, atomic compare-and-set promise or compatibility format.

## Verification scope

Retain the existing composer queue, shared-draft rollback, draft-store ordering,
prompt-dispatch closure, acknowledged deletion, runtime replacement and composer
interaction assertions. Adapt fixtures through real owner commands or the
persisted restore seam, rather than exposing test-only state setters. A held
steer with typing away and back characterizes revision-owned consumption.
Admission, acknowledgement and filesystem ordering are behavioral properties;
readonly declarations do not prove them. Source/behavior acceptance is pending
until the complete production and caller migration is frozen and reviewed.

## Direct caller closure and retained resources

The workspace screen and queue widget render `ComposerObservation` and copied
attachment values. Their edit/remove callbacks carry attachment IDs or stable
opaque queue IDs. Preview rendering receives the existing attachment adapter's
read capability; runtime uploads receive copied metadata/bytes and return an
attachment receipt. `ProfileChat` no longer exposes text, attachment lists,
queue entries, uncertainty, queue-edit buffers, pause, preparation, submission
or persistence fields. The shared-draft review and Home receive
`ComposerSavedWork`, rather than the mutable adapter snapshot.

`QueuedPromptDraft` remains the existing private-in-use persistence/composer
record. Its uncertainty is final; attachment records are mutable only within
that existing codec/upload seam. The workspace deletion coordinator converts
adapter records immediately into immutable cleanup receipts. Raw store reads in
verification fixtures inspect persisted file/acknowledgement evidence; they do
not supply presentation or submission state. No second codec or record version
is introduced.

Standalone transcript/retention fixtures explicitly compose the same required
owner and dependencies. Saved-work fixtures seed the existing codec, then call
the production restoration command; they preserve its missing-file validation.
One former fixture directly appended a new mutable file during a reserved queue
save. That was not a supported UI action (attachment admission was already
closed). It now verifies public rejection without consuming the unadmitted
caller-owned file, while retaining newer typing rollback and the original
admitted file. The byte-capture fixture replaces an immutable queue value in
its input list instead of assigning a now-final uncertainty field; attachment
receipt mutation and captured persisted values remain asserted.

The Logs rendering fixture has a direct import of the newly separated
`admin_logs_page.dart`; coherent verification requires that independently owned
operations extraction. The existing bounded attachment preview is also a
production dependency of both the original composer witness and this slice.

The extraction does not establish an atomic filesystem/preferences move,
post-dispatch cancellation, or engine/GPU allocation bound. The existing store
preserves its save-destination-before-remove-source/rollback behavior; admitted
persistence and submission settlement may finish after workspace retirement.
New commands and preparation are revoked immediately. Render acceptance and
source/behavior verification remain Root's serialized responsibility.

The existing `ARCH_RETIRED_DECLARATION` guard rejects the exact removed
`ProfileChat` draft, attachment, queue, editing, pause, preparation and persistence
declaration identities in the controller's containing library, including actual
parts and forwarding getters. It permits active runtime facts and unrelated
homonyms. This finite declaration check does not detect renamed duplicate work
stores or prove queue delivery, transfer ordering, rollback, cleanup or revision
consumption; those remain the behavioral obligations above.
