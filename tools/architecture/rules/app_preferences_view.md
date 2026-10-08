# Completed settings views and persisted-preference APIs

`ARCH_APP_PREFERENCES_VIEW` rejects calls and captured method references to the
published `SharedPreferences` persistence/read API in three completed libraries:

- `lib/core/screens/app_settings_content.dart`: `AppSettingsContent` and its state/helpers.
- `lib/core/widgets/text_size_settings_card.dart`: `TextSizeSettingsCard`.
- `lib/core/widgets/composer_action_settings.dart`: `ComposerActionSettings`.

It also checks only the actual canonical `HomeScreenState` class in `lib/main.dart`,
including its methods, fields and closures in that class or its actual authored
part. The rest of `main.dart` stays outside this completed scope: bootstrap,
startup notification/microphone permission policy and shared-draft composition
remain separately inventoried. The three original library scopes are unchanged.

Actual authored parts share their containing library's scope. Missing canonical
classes, malformed/ambiguous part ownership and unresolved selected accesses fail
input instead of silently shrinking the completed scope. Source classification
changes cannot exempt these exact libraries.

```sh
dart run tools/architecture/rules/app_preferences_view.dart --json
dart run tools/architecture/tests/app_preferences_view_test.dart
dart compile exe tools/architecture/rules/app_preferences_view.dart -o build/app-preferences-view
dart run tools/architecture/tests/app_preferences_view_test.dart --compiled build/app-preferences-view
```

Options are `--root PATH`, `--roles PATH`, `--sdk PATH`, `--json`.
Exit0 accepts; exit1 emits `ARCH_APP_PREFERENCES_VIEW` with declaration-provenance
access path/line; exit2 emits typed `INPUT` for invalid/unsupported inputs.
Source and AOT use the unchanged validated SDK helper. Explicit invalid SDK input
fails even with no access candidates; compiled fixture commands pass a real SDK.

A parsed lexical prefilter selects published method names, including bare
inherited captures, while proving narrow local parameter/field/getter shadows.
It keeps initializer/body traversal and qualified/cascade accesses. Resolved
elements must belong to class `SharedPreferences` in
`package:shared_preferences/src/shared_preferences_legacy.dart`, the currently
locked package's actual declaration. This published package filename establishes
provenance; it is not an application compatibility alias or a storage reader.
Fixture resolution imports the real pinned package, not a guessed replacement.

The guard covers reads, writes, reload/getInstance and public cache/setup methods
of that class, including prefixes, typedefs, re-exports, cascades, extensions
declared in the completed library, inheritance and method tearoffs. Conditional
authored dependencies of candidate libraries fail2 until all branches can be
verified. Unrelated same-name APIs/extensions and owner-generated callbacks are
valid. Keeping a typed raw `voicePreferences` object and forwarding it to the
unfinished voice workflow is valid; no storage operation is issued or captured.

The frozen original views contain two actual directly resolved reads, in app
settings and composer-action settings. The original text-size view's separate
wrapper is outside this direct-API property; retired-declaration/caller closure
owns that wrapper. No claim of three detected old direct reads is made.
The WorkspaceEntry predecessor Home class adds its actual two remembered-entry
reads and one unobserved write. Root owns original exit-1 and adopted exit-0
production proof; this guard source handoff launches no SDK jobs. Three bounded
Home fixtures cover raw read/write, typed owner with unrelated bootstrap/permission
and homonymous local APIs, and unresolved access. They supply the existing source
CLI representatives for exits 1/0/2; all prior detector fixtures remain.

This is an access-provenance property, not persistence/lifecycle verification.
The [preferences contract](../../../plans/001-app-preferences-contract.md) links
controlled ordering/restoration/invalid-state tests. Generic helper calls that
perform storage outside these libraries, additional package API classes, dynamic
reflection and creation of a second application owner are separate properties.
For Home, delegates defined outside the selected class remain outside this finite
declaration scope; the guard does not claim all workspace-entry policy is removed
from the mixed application entry library.
Do not infer those properties from zero direct findings. A focused independent
owner-construction guard can protect injected-owner identity separately.

The host wrapper executes both the actual production command and public fixture
proof. Both quality workflows require the production command; actual policy
fixtures reject omissions in each workflow and also protect against conditional,
fixture-only and swallowed enforcement.

The numeric local-feedback budgets are **12 seconds for the source command**
and **0.5 seconds for the standalone compiled command**. Root accepted them from
first-invocation and three repeated source/AOT samples on a fixed 299-file
production scope with the pinned Dart 3.12 SDK. Complete source hashes, binaries,
host details and samples stay private under
`/tmp/wing-six-guard-quiet-feedback-checkout/build/architecture-program/quiet-feedback/`.
Compare future samples on that same host, SDK and input configuration. Clock
noise in CI is informational and cannot change the deterministic rule verdict.
These checks establish this access property and feedback contract, not full
feature, application or native acceptance.
