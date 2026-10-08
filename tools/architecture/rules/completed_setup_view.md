# Completed connection setup view boundary

`ARCH_COMPLETED_SETUP_VIEW` checks the explicitly completed
`lib/core/screens/connection_setup_screen.dart` library. It rejects resolved
canonical connection/auth/probe construction, setup registry operations,
Cloud/probe operations and address/header resolution returning to that view.
The owner is `ConnectionSetupSession`; the view consumes immutable facts,
validation results and commands. Modal text/header drafts and unrelated
same-spelled UI declarations remain valid.

The rule uses analyzer declaration identity, not variable names or strings.
Calls, constructor/factory references, method/function tearoffs, prefixes,
aliases, barrels, declaration parts, cascades and inherited naked member
references are covered. Comments and strings do not produce findings. Selected syntax, SDK provenance, reachable namespace syntax/ownership, and
unsupported selected parts or conditional imports are checked unconditionally.
A parsed candidate pass can avoid semantic resolution when explicit
receiver declarations establish unrelated UI/framework ownership. Namespace
syntax, part ownership and supported conditional provenance are validated
unconditionally. Named declarations (including top-level variables and named type/extension
declarations) are cached once per library; imported homonyms remain ambiguous. Export lookups
traverse only a requested name, honor import/export combinators, and memoize the
complete answer after traversing any export cycle; they do not build and merge
all transitive namespace maps. A unique unshadowed class's single own static const string-literal field is a passive
fact, rather than construction or a forbidden operation. This narrowly covers
the existing portal link. Constructor calls/references, aliases, inherited
members, expression chains, uncertain constants and canonical operations retain
semantic checking. Unknown receivers, shadowed names, aliases, inherited
operations and dynamic candidates
remain conservative candidates and use the analyzer's actual declaration
identity. Candidate semantic errors are input errors.

This rule deliberately delegates **noncandidate semantic errors** to the
mandatory ordinary SDK analysis gate. Its fixture suite proves both results for
the same unrelated invalid return: boundary exit 0 and SDK analysis failure.
Boundary exit 0 alone never establishes valid Dart. External SDK/framework
conditional export selection also belongs to standard SDK analysis; conditional exports outside the validated SDK/framework roots are
unsupported provenance. The prefilter does not modify
source bodies or infer general expression types. This is
one finite list of canonical setup operations. It does not establish all possible
business calculations or hidden wrapper/whole-program flow. It does not prove
cancellation, current membership, persistence, secret preservation or HTTP
ordering; those require the public behavioral suites.

Run from the application root:

```sh
dart run tools/architecture/rules/completed_setup_view.dart
dart run tools/architecture/tests/completed_setup_view_test.dart
flutter test test/completed_setup_view_guard_test.dart
```

The independent command accepts `--root PATH` and optional `--sdk PATH`.
A compiled executable discovers the same SDK from validated package-config
Flutter provenance through `tools/architecture/dart_sdk.dart`; it requires no
SDK-adjacent binary or PATH fallback. Exit 0 means clean, 1 means findings and
2 means invalid/unsupported input. All fifty-eight previously accepted invalid/valid/unsupported fixture payloads are retained.
The existing cases protect prefixed field types, local/pattern/loop shadows,
inherited operations, aliases, cascades and unrelated local overrides. New
requested-name cases cover cycles, prefixed aliases through cycles, repeated
unrelated member lookup, hidden imports, passive constants and unresolved
constant prefixes. Variable/type import collisions and duplicate members remain
input errors; bounded generic type parameters cannot borrow an unrelated imported
class proof, while an unrelated generic parameter remains valid; hiding an unrelated homonym remains valid. Both prior CLI indirection cases and new cycle/constant
cases remain explicitly selected for source and freshly compiled execution. Actual
source/AOT CLI 1/0/2, invalid SDK 2 and the explicit standard-analysis dual proof
are exercised by the independent runner. The ordinary host wrapper checks the
production view plus these independent fixtures; full ordinary host testing is
the mandatory CI gate. The aggregate registration is coordinated separately.

The included-path-only successor is preserved separately for comparison; it
retains unconditional semantic resolution. This successor retains the approved candidate/standard-analysis responsibility
split and removes an unnecessary whole-view resolution caused by its permitted
portal string constant. Correctness checks run before
quiet feedback measurement; running under concurrent load is not timing evidence.

The requested-name successor retains all original fifty-eight fixture payloads
and passes seventy-four cases, including real source/fresh compiled CLI proofs.
Its accepted local-feedback budgets are **12 seconds for source startup** and
**2 seconds for a standalone compiled invocation** on the recorded host/SDK.
Root measured first-process startup and median three repeats against the same
complete 1,221-file checkout, after every compiler/fixture/analyzer job ended.
These lower budgets include margin over the observed peaks; unchanged compiled
control guards also stayed within their existing budgets. Input/source/binary
hashes, raw samples, host configuration and the comparison with the slower eager
namespace implementation remain private under the coherent acceptance checkout's
`build/architecture-program/quiet-feedback/`. Later comparisons must use the same
host/configuration. Cold means fresh-process startup, not flushed OS caches;
CI timing is informational and never changes correctness exits. This acceptance
does not establish full application, native/device or whole-deletion completion.
