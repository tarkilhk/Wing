# Backup ownership contract

Status: shared-owner extraction implemented; focused owner/visibility behavior
accepted. Reader and delivery follow-ups have original RED evidence; their final
acceptance and broader native/full-suite gates remain pending.
This slice changes local configuration ownership and uses no Hermes endpoint.
Saved Cloud connections continue to require a new sign-in after restore;
rotating OAuth grants are never exported.

## Original behavior and costs

Before this extraction, `HomeState` sequenced picker, passphrase sheet, export/import and delivery. Only
export was admitted once; overlapping imports were possible. `ConfigBackupIo`
constructed `ConfigBackupService`, which independently read and wrote canonical
preferences. Imports committed the connection manager first, then wrote settings
one at a time. A later setting failure did not undo the connection commit.

The original codec reader trimmed dashboard passwords. Public plaintext and
encrypted roundtrip regressions established the loss before the reader was
changed to preserve exact bytes.

The first section of `config_backup_card.dart` contains live shared sheets;
`ConfigBackupCard` itself remains a removal candidate. A resolved/root census must
prove its callers before removing the class or its exclusive tests. Live sheet
behavior and Studio rendering coverage must remain. `verbose_mode` had
no production consumer outside the former backup service. A hash-bound
all-authored root review authorized its removal; export omits it and import
reports it skipped without changing its unsupported stored value.

## One settings authority

The application-root `AppPreferences` instance owns canonical backup snapshot
reads and sparse restore writes. Neither `ConfigBackupService` nor the platform
adapter may hold `SharedPreferences`, enumerate raw preference keys, or invoke
raw preference writers. The backup owner borrows the root instance and never
constructs or disposes a second preferences owner.

Snapshot and restore commands join the existing FIFO before publishing pending
state. Listener reentry must not place a newer write before the admitted command.
A queued snapshot performs a private fresh observation; calling public `reload`
inside the same FIFO would deadlock behind itself.

Export includes valid explicitly present settings, preserving sparse absence.
It refuses invalid or unverified canonical storage rather than exporting a
retained value, omitting a broken field, or materializing product defaults.
Import validates the complete supplied patch before writes, restores only its
accepted fields, and never repairs an unrelated malformed field. Unsupported or
invalid preference entries in the input remain explicitly skipped.

Portable connection visibility remains supported. Typed logical connection IDs
and `SessionVisibility` values use this **same** preference FIFO. Controller
initial reads and choices must move to that authority before backup restore can
write visibility; an independent backup writer would race the controller.
The API does not accept arbitrary storage keys.

The restore operation captures original values and absence inside its reserved
FIFO slot. On failure it attempts to restore every attempted field, verifies
the outcome, and reports precisely which fields remain unverified. Pending
runtime controls retain their previous confirmed facts; they do not advertise
the incoming values as confirmed. Unrelated invalid fields remain invalid.

## Backup module and UI boundary

One `BackupSession` per Home lifetime borrows the connection manager, shared
preferences owner and a platform-only `ConfigBackupIo`. The adapter owns app
version lookup, bounded file intake and delivery. The session owns attempt
admission, validation, codec use, storage sequencing and sanitized outcomes.

An export or restore attempt is admitted before picker or modal work. Only one
attempt may be active. Opaque captured attempt identities fence canceled,
replaced and closed work. Backup contents, connection secrets and passphrases
remain operation-private; passive UI state contains only safe status and
results. The UI retains text controllers, sheets, navigation and rendering.
It forwards commands and presents the owner's outcome without interpreting
wire maps, reading preferences or deciding storage order.

Plaintext export is an explicit supported choice. Encrypted export requires a
nonblank passphrase of at least eight characters with exact confirmation;
validation belongs at the owner boundary as well as the sheet presentation.
Password and passphrase bytes are never trimmed or normalized.

Closing the route before a storage commit begins causes zero storage effects
and prevents late delivery. Once a durable owner operation is dispatched, that
owner finishes reconciliation even if the route closes; the closed session
publishes no later UI result. Failure or uncertain settlement never schedules
automatic replay.

Export delivery admission is the call to `SharePlus.share`, after temporary
lookup and private file preparation have completed and the captured session
still authorizes the offer. A close before that call causes zero share calls;
an accepted private write may finish but its undispatched stage is removed.
Each export owns a distinct staging directory, so a newer export cannot mutate
an earlier recipient's file. Once the share API accepts the offer, its plugin
may continue preparing the native request after route closure. The session
cannot revoke plugin-internal work and publishes no late result. The admitted
file remains available after chooser completion because recipient reads may
continue; this is not a promise of immediate post-share file reclamation.

## Honest partial restore

Connection import remains the connection manager's existing verified secure
storage transaction. It completes before settings restore. A settings failure
therefore returns a typed partial outcome: connections confirmed, with settings
failed/restored/unverified as observed. Consumers refresh confirmed connection
facts even when the settings outcome is unsuccessful.

This design does not roll back the manager after a settings failure: replacing
connections can retire OAuth owners and is not a safe inverse operation. It
does not promise atomicity across secure storage and preferences, or a new
process-death journal. The existing canonical version 2 format remains the only
format; no aliases, migration readers, legacy defaults or grant fallbacks are
introduced.

The version 2 reader requires every field always emitted by the current writer.
Nullable connection values remain explicit nulls; missing fields do not become
product defaults. Creation time must be the writer's UTC ISO representation;
metadata types, integer format version, ports and header maps are validated.
Cloud identity fields remain optional exactly as the writer emits them. No
format upgrade or legacy reader is introduced. Generic tagged preferences stay
a codec representation: the service's canonical catalog decides which imported
settings are supported.

## Behavioral acceptance

Existing public anchors are `config_backup_test`, `config_backup_service_test`,
`backup_safety_test`, `home_config_restore_test`, `connection_icon_storage_test`
and the shared-sheet Studio layout cases. Root-owned native backup/file transfer
tests verify actual picker and delivery behavior; host tests alone do not prove
those platform seams.

Required controlled cases, implemented one vertical slice at a time:

- Exact password roundtrip through plaintext and encrypted codec paths.
- Snapshot waits for an admitted settings write and its failed-write rollback;
  listener reentry cannot reverse physical storage order.
- Sparse restore preserves absence and unrelated malformed fields; failed
  writes roll back all attempted fields, with precise unverified rollback facts.
- Closing before storage begins causes no import/write/delivery; closing after
  dispatch preserves truthful durable reconciliation without UI publication.
- A second export/restore attempt cannot overlap a held first attempt.
- A connection commit followed by settings failure reports the partial result
  and exposes the confirmed connection state without replay.
- Visibility restore and a newer controller choice share ordering and cannot
  overwrite each other through independent raw writers.
- Live passphrase sheets retain cancel/plaintext/encrypted/confirmation behavior
  and merge/replace controls in both themes and enlarged text.

A narrowly scoped semantic guard can forbid canonical backup transport/storage
operations in completed backup UI and raw preference access in the service. It
cannot prove FIFO ordering, rollback, timing, disposal or absence of secrets;
those remain controlled behavior and platform acceptance obligations.
