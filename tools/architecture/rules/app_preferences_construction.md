# ARCH_APP_PREFERENCES_CONSTRUCTION

One production placement property: statically resolved calls and captures of the
canonical `AppPreferences` constructor belong directly within the actual top-level
`createApplicationDependencies` function body in
`lib/core/services/application_startup.dart`. Nested closures/local functions,
class methods, sibling functions and `lib/main.dart` are not exempt. Consumer widgets, sessions and services borrow the injected owner.
Type annotations and the constructor declaration itself are legitimate.

```sh
dart run tools/architecture/rules/app_preferences_construction.dart --json
dart run tools/architecture/tests/app_preferences_construction_test.dart
dart compile exe tools/architecture/rules/app_preferences_construction.dart -o build/app-preferences-construction
dart run tools/architecture/tests/app_preferences_construction_test.dart --compiled build/app-preferences-construction
```

The independent rule accepts `--root PATH`, `--roles PATH`, `--sdk PATH` and
`--json`. Scope is every production Dart source under `lib`, independent of role
classification. Test, integration and tooling roots may legitimately construct
their own owners and are outside this production rule. The host wrapper runs
both the fixture proof and actual production CLI. Parent quality workflows must
also invoke the production command without swallowing its exit status.

Before filtering, authored namespace and part targets must belong to the
shared parsed snapshot. Authored imports/exports or actual production-library
parts outside `lib` return a specific safe INPUT2 rather than silently escaping
inspection. This includes file URIs and package-config targets within the
checkout. The current shared snapshot cannot represent those outside units;
future support must add true containing-library provenance before accepting
such input. Test/tooling files used as production-library parts are not separate
legitimate test roots. Normal test/tooling entry points remain outside the rule.

A parsed candidate filter follows typedef spelling chains inside that supported
snapshot and includes constructor syntax, superclass clauses and mixin
applications. After complete provenance/conditional checks, candidates within
the actual application bootstrap body need no semantic identity: every canonical
construction at that syntactic location is permitted. The same AST placement
predicate is used by resolved inspection. A candidate outside that body always
requires semantic inspection, including one beside a permitted call in the same
library. The filter makes no canonical identity decision. Resolved `ConstructorElement` declaration provenance must
identify class `AppPreferences` in the actual canonical owner library. Prefixes,
barrels, aliases, unnamed/named captures, factory redirects, explicit/implicit
superclass calls and super-parameters retain their resolved targets. An implicit
default constructor or mixin application's generated constructor is checked
through its resolved superclass constructor. Actual URI/named parts retain
their containing library; the manifest cannot make a consumer part of bootstrap.

Missing canonical declarations, malformed/ambiguous parts, unresolved candidates
requiring semantic identity and conditional provenance requiring branch-specific
proof fail input. General SDK semantic errors solely inside an otherwise
permitted application bootstrap body are outside this placement rule, just as errors in
source with no constructor candidate are outside it. Mandatory ordinary
Dart/Flutter analysis checks those errors. A fixture explicitly verifies this
input-contract refinement; malformed parsed input and invalid SDK still fail.
Invalid explicit SDK input fails even without a construction candidate. SDK
discovery uses the shared validated helper. The locked analyzer's private named
parameter support is enabled only in the resolver's in-memory options overlay.

Exit0 accepts this placement property; exit1 reports stable
`ARCH_APP_PREFERENCES_CONSTRUCTION` diagnostics and exact source locations;
exit2 reports safe `INPUT`, without source values or credentials. Standard
analyzer lints do not express this project-specific placement requirement.

The private counterexample replaces WingAppState's borrowed-owner assignment
with a new owner over the same preferences store. Its ordinary source analyzer
and the existing direct-preferences-view guard both accept the source. This
guard rejects that constructor outside bootstrap. The real public composition
regression checks that an external confirmed theme choice reaches rendered
WingApp/Home, public consumer references retain injected identity, and retiring
the settings consumer leaves the root owner usable. WingApp itself owns the
root owner and disposes it after its consumers.

This does not establish a dynamic exactly-one-instance guarantee. Two calls or
a loop inside bootstrap, invocation counts of a captured constructor, external
factory callbacks and reflection remain outside placement. Arbitrary factory
behavior, shared state propagation, FIFO, rollback and disposal require public
behavioral tests; matching a constructor name cannot prove those properties.
No blanket factory, async or file-size ban is introduced.

The original 39 fixture payloads are unchanged. Two additional valid-language
cases cover a file-URI authored alias and a true production part physically
outside `lib`. The original production CLI incorrectly returned 0 for both;
the successor returns explicit INPUT 2. These valid Dart inputs have no
successful placement proof until the shared snapshot supports their ownership.

The provenance successor passed all 41 API fixtures, together with the actual
source and freshly compiled AOT CLI status matrix: invalid 1, valid 0 and unsupported input 2,
including invalid SDK and parts. Scoped SDK analysis reported no issues. The
previous 39-fixture freeze production source/AOT commands reported zero findings.
At that provenance freeze, successor production, quiet budgets and serialized
host/composition acceptance were pending; its functional proof made no timing
claim. Timing under concurrent work is not a feedback-budget acceptance
measurement.

The original quiet performance evidence is retained at
`/tmp/wing-six-guard-quiet-feedback-checkout/build/architecture-program/quiet-feedback/feedback-results.json`,
with exact 1,202 authored input hashes at
`/tmp/wing-six-guard-quiet-feedback-checkout/build/architecture-program/quiet-source-hashes.json`.
No feedback budget was accepted. Recorded timings remain in that private report,
as required by the performance evidence policy. The demonstrated cost
was resolving the full bootstrap library merely to accept a constructor already
within its permitted body. The optimized successor preserves all 41 prior
fixture payloads and verdicts and adds four cases: permitted nested alias
capture, a forbidden capture beside a permitted call, the explicit SDK-semantic
boundary, and still-unsupported conditional bootstrap provenance. All 45 API fixtures and actual source/fresh-AOT CLI 1/0/2 matrices passed,
including invalid SDK 2. Scoped SDK analysis reported no issues. Fresh production source and AOT commands both returned 0 with zero findings
across 299 lib files; their input hashes were unchanged before/after. Their
correctness evidence is recorded separately; quiet comparison and
a numeric feedback budget remain pending. Measurement under concurrent work
cannot accept a speed budget.

The subsequent complete 1,204-file snapshot accepted this rule's feedback
scope, with a **20-second source command** and **2-second standalone AOT command**
budget on the recorded host and SDK. Source timing includes SDK tool startup;
the compiled command avoids repeating compilation. All first/repeated samples
returned 0 and all authored hashes stayed unchanged. The earlier unbudgeted
slow revision and unchanged-guard controls remain private comparison evidence.
Later matching acceptance must fit these thresholds; noisy CI timing never
changes the deterministic diagnostic verdict. Raw samples, binary hashes and
budget disposition are under
`/tmp/wing-three-optimized-guard-feedback-checkout/build/architecture-program/optimized-feedback/`.
This accepts the finite placement feedback scope only; full application and
aggregate acceptance remain pending.

The current startup owner is composed by top-level `createApplicationDependencies`
and injected into WingApp by `main`. The previous rule exempted `main` and rejected
that shipping constructor. The successor recognizes only the exact factory
library/function and direct body ancestry, in both candidate and resolved paths.
Canonical alias/captured constructor detection remains resolved outside that
body. A same-name method, local function, different library or deferred nested
closure cannot inherit the exemption. Existing main-bootstrap fixtures are
migrated to the actual seam; the deferred nested-capture case now rejects. Seven
additional cases cover the shipping record factory, direct alias capture, main
delegation, forbidden main construction and library/method/local homonyms.
No compatibility exemption for the retired construction location is retained.

This private source freeze has no SDK execution claim. Parent acceptance must
run the independent API/CLI fixture matrix, actual production command, ordinary
analysis and existing public composition regression. Historical timing evidence
above applies to its stated source freeze; current timings remain unmeasured.
