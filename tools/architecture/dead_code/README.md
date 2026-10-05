# Resolved dead-code prework

This directory provides bounded deletion evidence for DC01/DC02 and DC04–07. Root phase1 clearance and the immediate source/census proof gate passed. DC01/DC02/DC04–07 have been removed; serialized root verification owns the live behavior gates. The exported proof matched the frozen phase1 source at the immediately pre-delete gate; all source hashes and the exact census were rechecked after resolution. This preserves reviewed pre-removal provenance, not an automatic liveness verdict or a post-removal hash snapshot.

## Evidence and reproduction

- `targets.json`: canonical declaring-library/member queries, including active transport controls.
- `resolved-proof.json`: exact source hashes, all resolved callers, unresolved candidate uses, semantic errors, owner inheritance and SDK context.
- `closure.json`: every target's per-scope counts and caller/line provenance, extra candidates and remaining obligations.
- `resolved_callers.dart`: a one-off semantic inventory using the cached analyzer and actual package config.
- `query_contract.fixture.json` / `prove_query.py`: independent synthetic CLI proof.

From the app root, with the existing toolchain:

```sh
../.toolchain/flutter/bin/cache/dart-sdk/bin/dart --packages=.dart_tool/package_config.json tools/architecture/dead_code/resolved_callers.dart . tools/architecture/dead_code/targets.json /tmp/wing-resolved-callers.json
python3 tools/architecture/dead_code/prove_query.py
```

The latest full resolution covered 661 authored Dart units and 53 queried targets: 817 references, zero unresolved candidate spellings, zero semantic errors and zero candidate-owner inheritance. The query binds hashes to the AST content and rejects source changes during analysis. The query also rejects authored census changes during analysis, and the immediate pre-delete check passed all hashes and the exact census. This export preserves pre-removal caller provenance, not a post-removal snapshot. The measured latest run took 31,908 ms (earlier runs 32,241–68,985 ms); this batch resolver is off the immediate feedback path. These measurements are informational, not a speed gate.

The cached analyzer 10.1.0 has an outdated experiment table for Dart 3.12's private named parameters. The query enables only that actual SDK feature through an in-memory analysis-options overlay. Application files/options stay unchanged. Without that tooling accommodation, the existing `GatewaySubagentActivity` constructor produces eight false resolver errors. Real resolver errors are never suppressed.

The fixtures passed: aliases, prefixed and conditional-selected barrel imports, cascades, tear-offs, extensions and parts resolve to their real declaration; an unrelated same-name member does not match. Dynamic dispatch remains an explicit unresolved obligation. A malformed semantic input exits 2 with a resolver diagnostic. The successful inventory CLI exits 0; that means the query ran, not that deletion is safe.

## Exact closure and retained transport

DC01 removes `ApiClient`, `GatewayChatClient`, `ToolProgressCallback`, and the unused `Session` model together. Their production references are confined to these declarations and their mutual use. The separate timeout/session-model test files exercise exclusively this removed surface. Remove obsolete groups from `connection_manager_test.dart`, preserving live connection-manager behavior groups. Remove resulting imports only after the analyzer proves them unused. The HTTP dependency has active callers elsewhere and is not part of this closure.

DC02 removes the queried high-level WS chat wrappers, per-request/per-session callback maps, connection-close listener registry, `RemoteFileAttachment`, `_ConnectionClosedListener` and `_gatewayResponseError`. Resolved shipping references are internal to this surface; external calls are obsolete tests. This requires deleting their fragments from otherwise active methods: stream-map/listener cleanup in `_handleClosedConnection`, wrapper response handling in `_handleMessage`, and per-session dispatch in `_dispatchEvent`. Preserve pending RPC completion, ready-handshake completion, global event dispatch and global connection notification in those same methods.

Retain `WsClient.connect`, `send`, `waitForGatewayReady`, `close`, `parseGatewayEvent`, model/reasoning helpers, `onStreamEvent`, `onConnectionChanged`, `_dispatchEvent`, their live private state and errors. `ProfileGateway` uses the raw request/ready/event boundary; the workspace uses model/reasoning helpers, and supported cross-client tests exercise them. A test-only symbol is not protected merely because a test exists: the resolved query also confirms `onGatewayReady`, `GatewayReadyCallback` and `isConnected` in the approved closure. `onGatewayReady` has its own invocation and test assignments but no shipping subscriber; `isConnected` only has test reads. The resolved `GatewayReadyCallback` typedef has only that field as a caller; preserve the actual ready waiter and `_connected` state.

DC04–07 remove `GatewayInterimTransition`, `GatewayNotificationLevel`, `GatewayNotification`, `GatewayTurnStatus`, `WingStatus` and `WingTokens.colorForStatus` with their exclusive obsolete test groups. Their production references are only self/closure references. The large insight/activity/theme files contain active types and helpers and remain. Preserve tests for active insight/activity/token behavior.

The authored root review found no Dart mirrors. The only `Function.apply` roots are navigation tests invoking already obtained widget callbacks, unrelated to these candidates. Native method/platform-view registration and app entry points are declared in `roots.json`; none dynamically names these Dart APIs. No alternate Dart entry point, integration test or authored tool called a candidate outside the documented closure. Recheck this root evidence at the stable deletion gate.

## Retain supported tools and platform roots

DC12's offline upstream-comparison tools have concrete supported purposes: regeneration-context projection, attachment-boundary extraction from an explicitly supplied checkout, desktop process projection and generation of the process-batch fixture with upstream provenance. They are opt-in executable roots, not production app callers, and must not be discarded merely because app imports cannot reach them. No framework install or backend change is needed for their retained purpose.

DC13's existing iOS Flutter scaffold remains a supported build/alternate platform root: `AppDelegate`, `SceneDelegate`, Xcode project, plists/storyboards/assets and native test entry points are genuine framework roots. This review does not establish feature parity or release certification. The user requested dead-code removal, not platform removal; no artificial platform-removal decision blocks the already rooted scaffold.

## Small prevention guards after deletion

Use the standard analyzer for unused private declarations/fields/imports/local variables; it cannot establish that a public API used only by tests is unnecessary. The implemented independent `ARCH_RETIRED_DECLARATION` rule uses the shared parsed snapshot and explicit `retired.json` canonical library/member identities. Its fixtures cover class/method/getter/field/enum/typedef declarations, alternate declaration spellings, real parts, unrelated same-name owners/libraries, local-function scope, and prefix/barrel aliases. Unowned parts fail closed; absence is the rule's property. Do not turn it into a speculative whole-program liveness engine.

A separate small root/orphan-library rule can compare the explicit roots with conditional import/export/part edges and report unrooted authored libraries for review. Framework/generated/vendor exclusions must be explicit. An unrooted report is a candidate, never permission to discard an opt-in tool, registered handler or supported fixture.

Keep this resolved caller query as a batch investigation. Shared immutable parsed input or compiled rule entry points may provide fast local guards, but each guard remains independent. Before claiming a new guard prevents regression, prove its real CLI diagnostic/nonzero exit on a bad artifact and zero exit on a valid artifact, plus the root quality-job invocation. Measure actual-checkout cold startup and median of three warm runs on the same host/configuration to justify its numeric budget. CI correctness is deterministic; timing is informational.

Before merging the eventual removal: refresh the proof, close all dynamic references, verify no removed reference escapes the closure, update roles/roots/inventories, run root's serialized analysis and relevant live behavior tests, and confirm genuine subtraction with no compatibility shim.

## Removal and guard acceptance

The batch removed `Session` and its exclusive model test, the exclusive old API timeout test, obsolete API/wrapper/value groups and the orphan `_PromptDisconnectPoint` test enum diagnosed by the standard analyzer. The remaining ready-handshake tests observe `waitForGatewayReady`; connection-close tests observe global connection events. No compatibility surface replaces the removed declarations. Scoped analysis of every changed production/test file and new guard returned zero issues. Flutter verification is serialized by root and is not inferred from this static result.

Run the independent declaration check and fixture proof with the existing SDK/package configuration:

```sh
../.toolchain/flutter/bin/cache/dart-sdk/bin/dart --packages=.dart_tool/package_config.json tools/architecture/dead_code/retired_declarations.dart --strict
../.toolchain/flutter/bin/cache/dart-sdk/bin/dart --packages=.dart_tool/package_config.json tools/architecture/dead_code/prove_retired.dart
```

The 20-fixture proof passed, including actual CLI exits 1/0/2 and exact rule/location assertions. The production declaration check returned zero findings on 256 files/255 libraries. Rule logic is parsed declaration ownership; import/alias spelling cannot relocate a declaration, and this rule makes no claim to detect dynamic use, all dead code or unused public APIs. Root owns aggregate/CI and host-wrapper integration.

Standalone local feedback retains the existing **10-second source budget** and now has an accepted **0.5-second standalone compiled budget**. Root verified first-run and three repeated source/AOT samples on the fixed 299-file/294-library production checkout with pinned Dart 3.12. The complete 1,202-file authored snapshot, exact source/binary hashes, host configuration and raw samples stay private under `/tmp/wing-six-guard-quiet-feedback-checkout/build/architecture-program/quiet-feedback/`. Compare future acceptance on the same host/SDK/input configuration; timing in CI remains informational and cannot change the deterministic verdict. The aggregate compiled budget is a separate contract and must still be rechecked after integration. This feedback result does not establish whole-checkout deletion or application/native acceptance.

Root-approved A03 declaration relocation is guarded by former widget library identity only: model choice/selection/special-choice values, intelligence selection, diagnostics controller and its former `_AccessResult`/`_Recovery` values. Their supported new model/service declarations remain valid, and UI `ModelSpecialOption` remains allowed. The property prevents misplaced duplicates returning to views without banning the moved public APIs.

DC03/DC10 pre-removal provenance is in `attachment-proof.json`: 667 physical authored Dart units, zero semantic resolution failures or unresolved candidate uses, all source hashes and the exact census rechecked immediately before approved edits. `AttachmentDraftService` remains active with seven test subclasses; removed REST-mode values and validation are not dynamic roots. Only its two image-preparation override signatures required updates. The exclusive REST test was removed; active limits, metadata sanitization, staging, upload/retry and cleanup behavior retain their existing suites. Qualified retirement entries also prevent the outer immutable providers busy field returning while accepting active busy fields on other state owners.

`dependency_asset_proof.json` records the separate parsed-directive/cached-package audit for DC08 and pinned nonrecursive Flutter folder expansion for DC11. The deleted parent-folder marker is not a runtime resource; explicit privacy, pricing, icon and font declarations remain. Root owns pubspec/lock changes and final resource acceptance. Pre-removal hashes are historical provenance, not a claim to describe the modified tree.

## Source and compiled SDK proof

The batch query now uses the shared validated `dart_sdk.dart` helper. Its optional
`--sdk PATH` configures tooling provenance; no application protocol compatibility
is introduced. Source execution finds the running SDK; a standalone binary
without checkout Flutter metadata requires the real SDK explicitly. Invalid SDK
or query input returns typed `RESOLVED_CALLERS INPUT` status 2 without publishing
a new proof. Query diagnostics omit manifest/source literals. The proof records
the actual analysis SDK path and version alongside source hashes and census.

```sh
dart compile exe tools/architecture/dead_code/resolved_callers.dart -o build/resolved-callers
python3 tools/architecture/dead_code/prove_query.py --compiled build/resolved-callers
```

The same independent authored-Git fixture exercises source and fresh compiled
query success (0), actual malformed semantic input (2), and invalid explicit SDK
(2). Malformed target manifests also return 2. Failed semantic resolution emits
only diagnostic codes/locations and does not publish a new inventory. It checks
four exact canonical method references, valid unrelated symbols, dynamic
obligations, part/barrel/conditional-selected provenance, physically deleted
tracked files, and that invalid SDK cannot publish a proof. The query has no
violation status 1: success establishes inventory output, never deletion safety.
No current whole-checkout deletion proof or batch-query speed result follows from
this bounded SDK regression. Preserve original AOT counterexamples and exact
source/SDK/binary hashes privately; never infer compiled resolution from a clean
production guard with no candidates.

Constructors use their declared analyzer name, so a named constructor is
`Value.fromMap` and an unnamed constructor is `Value.new`. Analyzer's presentation
`displayName` already includes the class; qualifying it again previously missed
real constructor callers. The paired source/AOT fixture checks ten exact
constructor occurrences: prefixed/aliased calls and tear-offs through conditional
barrels, a part call, and explicit `this`/`super` initializer calls. An unrelated
class with the same constructor name is excluded. Each reference records the
canonical declaring file, fragment offset and line; the constructor's child
identifier does not count the same syntax occurrence twice. Implicit superclass
construction and dynamic factory reachability still require reviewed closure
evidence; inventory success is not deletion approval.

Pass `--evidence-dir` to `prove_query.py` to retain private exact input hashes,
commands, source/AOT exit statuses, inventories and input diagnostics. Preserve
the prior source and compiled binary before a new proof revision. No additional
linter or whole-checkout deletion acceptance follows from these bounded fixtures.

## Preferences and backup retirement boundary

The coherent caller/root review authorizes eleven additional qualified identities:
`VoicePreferences`/`VoiceProcessing` in their former service;
`ComposerAction.fromPreference` and `SessionVisibility.fromStored` in their model
libraries; the former text-size store, enum and private multiplier scaler;
`ConfigBackupService.exactPreferenceKeys`/`isBackedUpKey`; and the Card/State
classes in the shared backup-sheet library. These entries prevent those specific
declarations or aliases from returning. They do not ban their spellings globally
or prove that any other declaration is dead.

The original manifest fails the added public fixture contract with
`retired-voice-preferences: expected 1, got 0`. With the scoped manifest extended,
all **45** independent fixtures pass, including actual source and fresh compiled
CLI exits 1/0/2. Each retired identity has its own invalid declaration case. The
alias case rejects reintroducing the former voice type as a typedef; legitimate
`AppVoiceProcessing`, `AppTextSizePreference`, `_AppTextScaler`, voice-session,
shared-sheet and bulk-service declarations pass. Same-spelling declarations in
unrelated libraries or member owners remain valid. Rule logic remains the
existing parsed ownership check, not a new resolver or compatibility layer.

```sh
dart compile exe tools/architecture/dead_code/retired_declarations.dart -o build/retired-declarations
dart run tools/architecture/dead_code/prove_retired.dart --compiled build/retired-declarations
```

These correctness runs were not a quiet runtime measurement. The earlier speed
record describes its stated older checkout; root must recheck current standalone
and shared aggregate feedback budgets after registration. Timing never changes
the deterministic declaration verdict. Removal still relies on the separate
hash-bound caller/root evidence and surviving behavioral tests, including live
backup-sheet coverage; this guard is only recurrence prevention.


## Profile selection store retirement

`ProfileSelectionStore` in its former service library is retired after its
callers moved to the shared `AppPreferences` selection owner. The pure
`ProfileSelectionCodec` remains the sole current identity/key codec. No storage
alias, alternate format, migration shim or preference deletion was introduced.
The immediate pre-delete semantic query covered all 862 authored Dart units,
with 27 self references and zero external, unresolved or inheritance candidates;
source hashes and the census matched before removal. Independent root review
found no dynamic/native/tool registration. The active owner behavior tests remain.

The retirement manifest now contains 88 scoped identities. All 53 fixture cases
pass, including actual source and fresh compiled CLI 1/0/2 outcomes. The new
invalid control rejects the former canonical declaration; the valid control
accepts the current codec/preference owner and an unrelated same-name class.
The guard protects recurrence of this reviewed declaration, not arbitrary dead
code or equivalent renamed implementations. Full-checkout deletion closure
remains pending.

## Notification and transport subtraction

The notification channel/ID namespace remains; its unused instance workflow is
removed. Production notification delivery stays in ChatNotificationCoordinator
and its actual native sink. GatewaySubagentActivity's obsolete completion alias
and JsonRpcError's unused guidance accessor are also removed. The exact declaring
identities were resolved against995 authored units; all production references
were confined to the removed notification workflow, with no unresolved target
spellings or inheritance. Static notification IDs/channels and similarly named
live event/history members remain. Exact retirement now checks constructors as
Class.new or Class.named, including actual containing parts. This is a bounded
subtraction, not the final whole-checkout dead-code verdict.
