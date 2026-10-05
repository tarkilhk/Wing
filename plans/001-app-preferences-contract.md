# App preferences: current schema and confirmed ownership

## Scope and ownership

`AppPreferencesSchema` defines twelve current device-owned settings. Its pure
choices and immutable observations import no storage, rendering or platform
module. `AppPreferences` receives the existing `SharedPreferences` instance and
owns ordering, confirmed publication, failure and reload eligibility. The app must
construct one owner and share it across settings, connected/disconnected routes,
runtime consumers and configuration restore. Injection now covers appearance,
text size, running action, notifications, main and workspace consumers. Voice
and backup migration remains unfinished; global writer ownership is not yet
established.

Connection credentials, runtime journals, profile colors, browser arrangements,
permission prompts and connection visibility retain their existing namespaces
and owners. Settings commands write one selected field rather than replacing a
captured snapshot. No repository wrapper or global singleton is introduced.

## Current values and invalid observations

### Restart profile selection and pending work

The canonical per-connection restart selection shares the `AppPreferences`
FIFO. Navigation can admit a newer selection while an earlier physical save is
held; the earlier caller joins the latest admitted settlement before reporting
its durable outcome. Selection publication follows queue reservation, uses a
separate passive channel and cannot rebuild unrelated appearance preferences.
Absent storage may use the genuine current discovery preference. Present
invalid storage and a valid saved name missing from the fresh roster require an
explicit available-profile choice; neither silently selects another profile.
Navigation success does not acknowledge that required repair. Its initialization
workflow stays open after a failed or unverified save. Only a settled valid
selection matching the current profile completes the existing restoration once.
A newer navigation admitted behind a held write returns without waiting; the
confirmed-selection listener later completes that same workflow. An unverified
outcome requires a successful read-only reload before another physical save.
Ordinary navigation after initialization and fresh absent-selection startup keep
their distinct policies; a standalone switch does not assume startup duties.

Pending chat owners remain independent of this selection. Before its first
journal snapshot, the workspace controller imports the complete existing
canonical journal into its unresolved-owner set exactly once for that lifetime.
Initialization and restoration may import it earlier, but notification recovery
can write before either runs. Subsequent writes never re-import old entries after
their verified restoration or settlement. A malformed list, row or failed read
blocks replacement and retains the stored bytes; no guessed empty journal or
alternate format is accepted. This is scoped to the single registered controller
owner for each connection identity, not arbitrary concurrent outside writers.

The public controller regressions exercise an unavailable restart selection,
notification recovery both before repair and before initialization, unreadable
journals, and later writes after old owners settle. Actual platform ordering and
entry-point timing cannot be established by a static symbol rule; these
behavioral checks own the retention invariant. Source inventory or key-ownership
lint alone does not prove it.

Absent keys receive declared fresh-install defaults without a storage write.
Present wrong types or unknown choices produce named field issues; they are
never coerced, mapped to old values or replaced with fresh defaults. The canonical
accent is `teal`; `mint` is not an accepted alias. Independent voice input/output,
retained unavailable Android voice identifiers and the three supported rates
remain distinct choices.

`AppPreferencesValues` exposes typed nullable fields. An invalid initial field
has no invented selection, while other valid fields remain available for repair.
A malformed later reload retains the prior confirmed value only for that invalid
field. Valid newly observed fields advance independently. Current issues remain
explicit even when retained values can form a complete display snapshot.
`storageVerified` requires no invalid observations, pending writes, unverified
restoration or failed reload; a retained snapshot alone cannot authorize export.

The new canonical catalog omits `verbose_mode`: its only production references
were the backup allowlist and validator, with no setting or runtime consumer.
This is not a storage migration: any old local value stays untouched. During the
backup migration, version 2 generic codec behavior remains unchanged; unknown
preferences retain the explicit skipped-count behavior. Owned present-invalid
preferences must surface an error rather than silently disappear from export.
The shipping backup service still uses its existing catalog until that migration.

## Storage and lifetime contract

Commands and explicit reloads share one ordered tail. A predecessor's failed
write and attempted restoration settle before the next command dispatches.
Admission reserves that tail before publishing pending state: a synchronous
observer's next choice cannot jump ahead of the accepted command. An idle
owner starts work in the invoking command's microtask context, rather than
retaining the construction context through an eagerly completed future. The
tail becomes idle only when its last reserved operation settles.
Only confirmed platform results advance saved choices. False/throwing writes
report a safe typed failure; failed restoration remains unverified. Commands for
that field require an explicit successful reload before further mutation.
Failed reload likewise blocks writes: the plugin may have cleared its cache,
which cannot authorize a guessed removal or rollback value.
Successful fresh reload retires the earlier unconfirmed-restoration directive;
it does not clear invalid-field issues discovered by that read. Failed reload
preserves the need to verify rather than presenting recovery as completed.

Closing the owner refuses new and still-queued commands. Already-dispatched
storage work finishes and reports its actual result without notifying a disposed
presentation. Reopening reads the actual stored preferences. Storage success is
the installed plugin's confirmation contract, not a claim about arbitrary power
loss or concurrent outside writers. Caller migration must remove outside writers
before the feature gate closes.

## Regression evidence and remaining migration

The original public `saveDevicePreference` regression holds an earlier write,
confirms a later choice independently on the storage platform, then releases the
earlier false/throwing failure. Both variants fail because the stale rollback
overwrites the confirmed choice. The immutable original source/test is retained
outside the checkout; the private log is
`build/architecture-program/app-preferences-concurrency-original-red.log`.

The replacement public owner tests use its ordered contract: the later command
stays undispatched while the predecessor is held; after its failure and attempted
restoration settle, the later choice must actually persist and survive a real reload.
Successful predecessor ordering, sparse different-field updates, invalid initial
repair, malformed reload, failed restoration/reload, owner closure and unchanged
observation identity have separate controlled cases. Schema tests cover accepted
values, explicit invalidity, canonical accent, immutable observations and retained
display facts versus current validity.

Verification: `flutter test test/app_preferences_test.dart test/app_preferences_schema_test.dart`.
Static lint cannot establish held platform outcomes, disk ordering, restored
cache effects or confirmed publication. The behavioral property
`APP_PREFS_ORDERED_SAVES` is guarded through the real public owner and controlled
preference platform. The precise completed-view rule supports caller
ownership; it must not claim to prove these temporal outcomes. The independently
implemented completed-view rule now has frozen source/AOT fixture and production
scan proofs; parent CI and performance-budget acceptance remain separate.

`test/app_preferences_command_queue_test.dart` preserves three public
regressions: a preconstructed owner settles a widget-clock choice; a reentrant
pending observer cannot replace a later accepted choice; actual platform writes
remain `iris` then `gold`, with `gold` retained in storage and observation. The
original emitted the reversed physical order. This is an admission/lifetime
property, not a reason to ban `Future.value` throughout the codebase.

Still pending: extract the route-owned Android voice settings workflow; integrate
backup through the shared owner; remove superseded preference types/helpers after caller proof;
move profile color storage/rendering responsibilities to their existing owner and
pure rendering helpers. This increment alone does not close the feature gate.

## Shared injection and completed controls

The injection increment gives `WingApp` one required `AppPreferences` instance,
created at app composition and shared with home, workspace controllers,
notification coordination and background monitoring. The app owns its lifetime;
controllers and routes borrow it. Standalone fixtures also explicitly share one
owner when they recreate controllers. Raw preferences remain available for the
unrelated journals and permission markers. The still-unmigrated voice and backup
writers remain an explicit incomplete boundary.

Appearance, text size and the default running action render immutable passive
controls from that owner. A choice returns only confirmed success for navigation;
the owner retains pending state and publishes safe failures after route closure.
Invalid fields have no selected control value and expose a repair notice. A
retained prior value is display history, not a valid stored selection.

Framework rendering cannot omit its theme or text scaler. With an invalid
initial appearance value it uses neutral appearance and the system scaler,
alongside a persistent explicit repair notice. A previously observed appearance
can remain on screen with the same notice. Repair opens settings above the
current route, preserving guarded editors. Selecting a canonical value is the
only repair; viewing or reopening does not write or reinterpret `mint`.

Notification and running-action authority checks only the relevant current
field. Invalid or unverified preview settings never expose message text;
unrelated invalid voice values do not disable confirmed notification settings.
A pending choice retains the previously confirmed authority until storage
confirms the change. It does not authorize the requested value, and
`storageVerified` remains false while a write is pending. A failed attempted
category change must not cancel an already posted notice. Ordered writes still
settle before the next choice dispatches.
A running chat without a valid default presents “Choose chat action”; a tap
opens named actions and does not dispatch one until an explicit selection.

Notification rendering rereads category eligibility and message-preview
authority after the held permission query, immediately before creating the
actual notification. Public output-sink tests exercise category and preview
changes during that await. Separate public owner tests hold a failing preference
write and verify retained action authority and absence of notice cancellation;
static lint cannot prove these dispatch or confirmation properties.

Additional verification: `flutter test test/app_preferences_controls_test.dart
test/app_preferences_settings_test.dart test/composer_action_settings_test.dart
test/composer_action_button_test.dart test/text_size_preference_test.dart
test/device_preference_test.dart test/wing_theme_test.dart
test/app_preferences_notification_dispatch_test.dart
test/app_preferences_pending_authority_test.dart`.
The completed-view raw-storage boundary guard must be independently implemented
and accepted with its own fixtures and production scan before this increment closes.
This does not establish global preferences ownership while voice and backup
still contain raw writers.

## Voice settings: route owner checkpoint

The storage seam remains the existing shared `AppPreferences` owner. A raw
voice-settings wrapper would leave callers responsible for stopping playback,
await ordering, closure checks, capability generations and invalid selections.
The selected interface instead places those obligations behind a route-owned
`VoicePreferencesSession`. It borrows the preference owner and a `VoiceDevice`,
owns its preview controller and publishes immutable controls, options and
recovery actions. The widget owns only text/focus/scroll, route construction and
framework-event forwarding. The route extraction is authored; focused behavioral and rendered acceptance remains pending.

The session owns capability observation generations, retained unavailable
language/voice choices, manual language validation, foreground preview
eligibility, stop-before-save and route disposal. It never caches another set of
saved preferences. A choice whose native stop is held must recheck route
authority before submitting a preference command. Once the shared owner has
dispatched a storage write, closing the route does not cancel that write or
forget its actual outcome. Capability results from an older refresh cannot
replace a newer observation; failed refresh retains prior observations with
explicit failure. Preview is local-only and never constructs a Hermes client.

Input and output operations consume separate immutable typed settings rather
than reading raw storage. Hermes input requires its valid processing choice;
local input additionally requires a valid recognition language. Hermes output
requires its valid processing choice; local output additionally requires a valid
voice and speed. Invalid settings for the unused engine cannot disable an
otherwise valid operation. Invalid active settings require explicit repair.

Stock was refreshed to `158fd638da1629c8e62caf9ade1515d162def8ab` before this
design. Inspected `hermes_cli/web_routers/audio.py` and `hermes_cli/web_models.py`:
transcription still accepts `data_url`, optional `mime_type` and the profile query;
speech accepts `text` and the profile query. Existing transport and profile
ownership are reused unchanged. The Android-only preview does not write profile
configuration or introduce a new endpoint.

Behavioral acceptance crosses the public session and real rendered widget:
held preview stop followed by closure sends no preference write; an already
dispatched write still settles; overlapping capability reads publish only the
latest result; background/closure stops preview; retained unavailable choices
are not rewritten; invalid fields stay unselected and can be repaired alone;
input/output remain independent; preview cannot call Hermes. Rendering requires
normal and enlarged text in both themes. A small resolved view rule can forbid
raw preference/native operation calls, but cannot prove these lifetime or
confirmation outcomes.

## Typed backup and connection visibility

Backup observes and restores only the twelve canonical fields and the named
connection-visibility namespace, through the same `AppPreferences` FIFO. A
queued export reloads storage privately and returns only explicitly present
values. It refuses malformed presence instead of exporting retained display
history or materializing defaults. A sparse restore captures actual before-values
inside the queue, permits a supplied valid value to repair that same malformed
field, and leaves unrelated issues and keys untouched. The result distinguishes
committed writes, attempted fields and unverified rollback. The first failed
write is attempted because storage can report failure after an external effect.
A closed owner after a held fresh read sends no new write; already dispatched
writes settle and reconcile their real outcome.

Connection visibility is a typed per-ID choice in this owner. Missing canonical
storage declares the fresh Chats default; present invalid storage has no current
choice. Its passive control exposes repair, pending and verification facts.
Registering an initial observation updates aggregate validity immediately.
No request may guess a visibility filter from an invalid value. The controller borrows this selection, listens for confirmed changes and owns
one guarded refresh. Four filtered request paths require a current selection;
invalid presence renders named repair choices. Its public false-write regression
was reproduced against the original setter before this migration; focused
acceptance of the new paired controller/browser remains pending.
Connections themselves remain a separate owner: backup orchestration reports
partial connection-first outcomes rather than claiming an atomic cross-owner
transaction or rolling back the connection manager.

`test/app_preferences_backup_owner_test.dart` controls actual platform writes,
held reads, false acknowledgements and failed rollback. Static shape checks
cannot prove disk acknowledgement, rollback or temporal FIFO; the public storage
regressions own those properties. Completed-view canonical-storage operations
are separately guarded by the precise resolved-symbol rule. The new voice route
and bulk APIs are authored checkpoints awaiting focused, broad and rendered
acceptance; this document does not declare global feature closure.

The session listing/search source scope was inspected again at current stock
`158fd638da1629c8e62caf9ade1515d162def8ab` in
`hermes_cli/web_routers/sessions.py`: both accept `exclude_sources`, with listing
source scoping applied to the count and paginated read. This preference does not
add an endpoint or alter profile routing. The independent connection-wide browser
index still explicitly reads All to retain its existing shared browsing data;
rendered filtering borrows the confirmed app choice and never guesses invalid
stored intent.

`ARCH_VISIBILITY_KEY_OWNER` enforces one narrower static property: production
calls and captures of the resolved canonical `SessionVisibility.preferenceKey`
member may occur only in the `AppPreferences` library and its actual parts.
Declaration alone is legitimate; a model self-call is not an exemption. This
rule accepts unrelated names, local shadows, ordinary enum use and owned parts;
imports, barrels, aliases, caller parts and cascades retain actual symbol
provenance. Conditional provenance requiring a branch-specific proof fails as
input rather than reporting a clean result. Literal or manually computed keys
are outside this symbol property; a source census is an inventory aid and the
public false-write/request tests still establish the storage contract.

Run `dart run tools/architecture/rules/visibility_key_owner.dart --json` and
`dart run tools/architecture/tests/visibility_key_owner_test.dart`. Its mandatory
host wrapper is `test/visibility_key_owner_guard_test.dart`, covering fixtures
and the actual production CLI. The fixture runner also accepts
`--compiled <fresh-guard-binary>` for actual compiled invalid/valid/input verdicts.
Source proof covers 27 API fixtures and real CLI exits 1/0/2. The fresh compiled
runner passes all 27 fixtures, including invalid SDK input. The actual original
296-file source reports three canonical accesses (controller and backup service);
the earlier repaired 301-file production reports zero. The refreshed fixed
299-file production scope also reports zero. Both quality workflows now require
the production command; actual omission tests reject its absence in each
workflow.

The numeric local-feedback budgets are **10 seconds for the source command** and
**0.5 seconds for the standalone compiled command**. Root accepted first-run
and three repeated source/AOT samples on the fixed production scope and pinned
Dart 3.12 SDK. Raw samples, host/configuration details, source hashes and binary
proofs remain private under
`/tmp/wing-six-guard-quiet-feedback-checkout/build/architecture-program/quiet-feedback/`.
Later comparisons use the same host, SDK and input configuration. CI timing
remains informational; it cannot soften correctness or make the rule's result
depend on wall-clock noise. Whole-feature and native acceptance remain separate.
