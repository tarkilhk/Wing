# Settings edit ownership contract

`ARCH_SETTINGS_VIEW_PROTOCOL` keeps completed settings views from calling or
capturing the canonical configuration/HTTP capabilities, parsing wire values,
or invoking domain validation. The route owns controllers, focus, scrolling and
dialogs. `SettingsEditSession` owns observation, edit intent, validation, conflict
choices, review and command lifetime. `ProfileAdministration.saveSettings` owns
fresh protocol preflight and readback; it uses the strict Dashboard mutation
capability, including authority checks after authentication and renewal.

The inspected unmodified upstream revision is
`f5a9361dcc66b0b972fd488b83129561509b3486`:
[config router](https://github.com/NousResearch/hermes-agent/blob/f5a9361dcc66b0b972fd488b83129561509b3486/hermes_cli/web_routers/config_env.py),
[model router](https://github.com/NousResearch/hermes-agent/blob/f5a9361dcc66b0b972fd488b83129561509b3486/hermes_cli/web_routers/models.py).
Config writes accept a sparse `config` map and acknowledge `ok`; stock has no
expected-version or expected-model mutation precondition. The captured model
pair is compared with canonical `model/info`, including an empty automatic
provider. Concurrent server changes after preflight remain possible. A response
or readback that cannot confirm a dispatched write requires explicit fresh
review and cannot silently repeat the request.

## Independent verification

```sh
dart run tools/architecture/rules/settings_view_protocol.dart --json
dart run tools/architecture/tests/settings_view_protocol_test.dart
dart run tools/architecture/tests/settings_edit_intent_test.dart
flutter test test/settings_edit_session_test.dart test/settings_owned_transport_test.dart test/settings_edit_lifetime_test.dart test/settings_edit_intent_guard_test.dart test/settings_view_protocol_guard_test.dart
```

The guard covers `settings-and-forms` view/presentation roles and the canonical
completed settings page. An AST prefilter only selects candidates. Diagnostics
require resolved canonical declaration/library identity; unrelated methods with
the same spelling are valid. Fixtures exercise aliases, barrels, parts,
cascades, inherited calls, function-valued capability fields and tearoffs.
Candidate accesses that cannot be resolved, or depend on a local conditional
import/export, fail with input status 2 rather than passing an unproved branch.
Bad fixtures exit 1 with diagnostic ID and exact file/line; valid fixtures exit 0.
Three fixtures exercise these statuses through the actual standalone CLI.

This is a finite protocol/parser ownership guard, not whole-program dataflow or
a proof that every business decision has left every view. An already-obtained
function passed into a view under an arbitrary name is outside its static scope.
Disposal, authentication races, conflicts and uncertain writes need behavioral
regressions: held config/membership/model reads retire without writes; held
authentication and 401 renewal retire without replacement HTTP; settled timeout
revokes still-open command authority; post-dispatch disposal retires publication
without inventing remote cancellation. The owner tests retain unknown toggle and
catalog observations, exact decimal percentages, disjoint server values and
explicit same-field conflict choices.

## Feedback procedure

Keep observations under ignored `build/settings-guard/`, not in public Git.
Record host, SDK, authored input count, four fresh `dart run` processes and four
fresh compiled processes. Compile the same entry point with `dart compile exe`;
record CLI wall time separately from its parsed-input and in-process rule times.
The cheap production path starts no resolver when no candidates exist. Resolver
fixture coverage is a separate acceptance batch. Timing is informational and
must never change deterministic exit status. Shared immutable graph invocation
can amortize parsing without merging unrelated rule logic.

The initial local feedback budgets for this guard are 15 seconds for a fresh
`dart run` process and 1 second for the compiled clean-check process on the
recorded host/SDK and full authored scope. These allow tooling startup variation
while keeping the compiled ownership check suitable for rapid local feedback.
Use the same recorded conditions when checking a regression; optimize a repeated
budget breach rather than raising the budget without evidence. A candidate that
requires semantic resolution has a separate 120-second fixture watchdog and is
not certified against the clean-path budget.


## Validated SDK for semantic and compiled proofs

The resolver uses the existing shared `tools/architecture/dart_sdk.dart` helper. `--sdk PATH` is validated even for a zero-candidate input; an invalid explicit SDK is input exit 2. Compiled guard binaries outside a configured checkout must receive the actual SDK explicitly.

`dart run tools/architecture/tests/settings_view_protocol_test.dart --compiled BINARY` tests the independent source CLI and compiled CLI against invalid (1), valid (0), and unverifiable (2) fixtures, including exact diagnostic ID/file/line and invalid explicit SDK on a valid no-candidate input. A zero-candidate production run is not evidence that the semantic resolver works. Keep compiled executables, exact source/SDK hashes and timing evidence in ignored `build/` or private acceptance storage; do not commit measurements.

Bare inherited getter/method capability capture is also selected and requires canonical resolved declaration provenance. A same-named local parameter/reference is accepted; fixtures protect both cases.

`test/settings_view_protocol_guard_test.dart` runs the actual complete-scope production CLI separately from its independent fixture runner in the full host test gate. Both properties are required.
