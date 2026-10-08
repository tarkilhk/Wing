# Completed model view owner boundary

`ARCH_COMPLETED_MODEL_VIEW` covers the accepted
`lib/core/widgets/profile_default_model_sheet.dart`,
`lib/core/screens/administration/admin_fallback_page.dart`, typed passive
`lib/core/widgets/profile_diagnostics_panel.dart` and completed
`lib/core/screens/administration/admin_defaults_page.dart` and the completed
`lib/core/screens/administration/admin_health_page.dart`. Add another view to
`completedViews` only after its business workflow has moved to a typed owner.
This is a completed-slice guard, not a claim that all views are clean.

```sh
dart run tools/architecture/rules/completed_model_view.dart
dart run tools/architecture/tests/completed_model_view_test.dart
```

The ordinary host wrapper is `test/completed_model_view_guard_test.dart`; it
checks all five production views and executes the independent synthetic fixture
proof, including real source and compiled CLI diagnostic/location and exits 1/0/2.
The current matrix has 57 cases; the previous 44 fixture payloads remain unchanged.
The fixture command compiles a temporary guard unless passed `--compiled PATH`.
Both compiled invalid/valid examples require semantic resolution; a clean syntax
prefilter cannot conceal failed SDK discovery. Missing SDK provenance returns
compiled input exit 2.

The rule parses the declared transport owner classes to collect their current
public method names, then resolves only candidate views. A diagnostic requires
the canonical declaration owner: ProfileGateway, ProfileAdministration,
DashboardClient or WsClient in their declared service libraries. Invocations and
method tearoffs are forbidden; constructor injection, scope labels and typed
edit-session commands remain valid. Inferred aliases, prefixes, typedefs, barrels
and cascades retain declaration provenance. Unrelated UI methods named `read` or
`call` pass. An unresolved candidate fails with input exit 2 instead of guessing.

The same boundary forbids exactly the canonical `ProfileDiagnosticsController`
commands `check`, `invalidate`, `updateModel`, `updateGateway` and `restore`,
declared in `lib/core/services/profile_diagnostics_controller.dart`. Calls and
captures use resolved declaring class/library identity, including inherited
commands, aliases, prefixes, barrels and cascades. The command names and actual
owner declaration are validated before the view scan. `snapshot`, passive
getters and notifier lifecycle methods remain valid, as do unrelated controllers
with the same class/member spellings. Health now delegates access review to its
captured callback instead of calling `checks.invalidate()` after navigation.
This is a finite canonical command boundary: it does not infer arbitrary policy
implemented in local helpers or prove temporal ownership, scope or ACK outcomes.
Those require the diagnostics/Health owner and public behavioral regressions.

The same boundary also forbids the canonical AdministrationRepository callable
fields `request`, `settingsWrite` and `ownedMutation`, whether invoked, captured,
or passed as callbacks. Provenance uses the owning class/library, including a
declaration in its part and unqualified inherited/extension getter captures;
unrelated same-spelling UI fields remain valid through
aliases, cascades, prefixes, barrel exports and typedefs. Typed Dart
`Function.call` is an intrinsic invocation with no member declaration; the guard
accepts that intrinsic while still inspecting the target for forbidden captures.

The same owner-boundary property includes `ModelCatalog.fromOptions`, `ConfiguredModel.fromInfo`,
`FallbackModel.fromConfig`, `HelperModelAssignment.fromResponse`,
`ModelDefaultsObservation.fromResponses`, `ModelProviderAccess.fromResponse` and literal
stock model field indexing on core `Map<String, dynamic>` / `Map<String, Object?>`
observations. It uses decoded string literals, so escaped field spellings are
checked. Typed UI maps, other UI keys and labels remain valid. This restriction
does not ban all maps. It deliberately does not establish interprocedural wire
provenance, computed-key dataflow, custom Map subtype behavior or every possible
business policy. Wrap wire observations in typed owner projections rather than
adding a suppression. Legitimate nearby UI fixtures demonstrate acceptance.

Malformed input, missing declared owners, direct conditional imports and view
parts fail closed. The current resolver checks the selected platform; transitive
conditional adapters require separate platform proof. It does not claim universal
all-platform resolution or detect code hidden inside another library's helper.
Dart does not accept backslash-escaped member identifiers; that raw fixture gets
input exit 2, while escapes inside string field keys are decoded normally.
Resolver SDK discovery is shared with the owned-mutation guard in
`tools/architecture/dart_sdk.dart`: validate explicit `--sdk PATH`, use the running
Dart SDK for source execution, or the actual package-config Flutter SDK root for
compiled/Flutter-host execution. Unsupported/missing provenance fails input 2;
the binary's parent directory is not assumed to be an SDK.

The prior quiet-host acceptance covered four views (809 authored lines), four
method owners and three canonical repository callable fields. They include cold
source startup and the median of three fresh source and compiled processes, with
the shared SDK helper and source/configuration hashes checked before and after.
SDK startup dominates clean checks; use the compiled entry for fast local
feedback. The original same-host/configuration budgets remain 10 seconds for
source execution, 30 seconds for one-time compilation and 100 milliseconds for
compiled feedback. The prior four-view scope passed them on Linux x86-64 with Dart 3.12.0
and analyzer 10.1.0. The added Health/diagnostics scope requires parent quiet acceptance against
those unchanged budgets. Raw SDK/host/input hashes and measurements stay outside Git
per `docs/PERFORMANCE.md`. Repeat acceptance under those same conditions; no OS
page-cache flush or source-result cache is implied. CI timing is informational
and cannot change correctness. Root owns aggregate/role registration.

```sh
dart compile exe tools/architecture/rules/completed_model_view.dart \
  -o build/completed-model-view-guard
build/completed-model-view-guard
```

Recompile after changing rule/shared model source, SDK or dependency configuration;
the binary always reads current views and owner declarations from the checkout.
Do not reuse a compiled rule after its own implementation changes.

The helper-defaults migration uses this same boundary property once its view
is accepted into the completed list. Its separate behavioral contract is in
`test/profile_model_defaults_session_test.dart` and
`test/profile_model_defaults_view_test.dart`. An opening helper intent captures
the complete task/provider/model/base-URL/reasoning observation; refresh,
confirmation and retry cannot replace that baseline. The owner reads the current
catalog and assignment, validates captured profile membership before calling
the transport, and fences retired operations at its own await boundaries. An uncertain committed write is
reconciled by observation without resending it. Reset also verifies endpoint
credential-key absence without exposing credential values.

Static syntax or symbol resolution cannot establish these ordering and delivery
properties. Controlled held I/O and confirmations exercise them at the owner
interface, while the real widget counterexample changes an endpoint after
opening the picker. The isolated original-view reproduction must fail that
widget's zero-POST expectation before the repaired version is accepted. Standard
Dart analysis enforces the intent's final fields; immutable lists and behavioral
tests enforce the retained snapshot. Stock `model/set` has no expected-version
argument, so a server write racing after the client's fresh preflight remains
outside this observed-conflict guarantee. The inspected current contract is
[official Hermes db45b44ab72af81974adfb01c9ecd6967f5bec29](https://github.com/NousResearch/hermes-agent/blob/db45b44ab72af81974adfb01c9ecd6967f5bec29/hermes_cli/web_routers/models.py).

The accepted helper owner invokes the strict owned-mutation capability. Its
controlled held-dispatch/consumer-timeout tests prove authority revocation after
settlement and route retirement. Main/fallback/settings physical transport
regressions separately hold authentication and 401 renewal at the Dashboard
boundary. These behavioral checks complement the view/owner guards; no static
syntax or symbol check establishes that ordering by itself.

```sh
flutter test test/profile_model_defaults_session_test.dart \
  test/profile_model_defaults_view_test.dart
```
