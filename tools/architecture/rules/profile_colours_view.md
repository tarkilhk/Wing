# Completed colour view persistence boundary

`ARCH_PROFILE_COLOURS_VIEW` protects exactly the `ProfileSelector` and
`ChatProfileBar` libraries and all their actual, uniquely owned parts in the
parsed authored `lib/` scope. Their typed `ProfileColorsSession` factory,
`ProfileColorsState`/`ProfileColorFact` rendering, owner-provided reload callbacks,
presentation colour mapping and delegated picker commands remain supported.

The finite property rejects canonical SharedPreferences/platform-interface,
AppPreferences and retired ProfileColorStore authorities; file IO, dart:convert
and crypto key encoders; construction of another ProfileColorsSession (including
constructor aliases and explicit/implicit super calls); and actual Flutter
channel/messenger authority references. A storage/encoder namespace exposed by
an import is rejected even when unused. Rendering imports exposing Flutter
channel names are allowed; accessing those authorities is rejected. Exporting
from either completed widget library is rejected. The exact current
`profile_color_v1_` prefix at the start of a literal or any interpolation text span is also rejected here:
persisted-key construction belongs to the owner. No diagnostic repeats literal
contents or hashes.

Parsed AST names and export edges only select possible violations. Actual
library/class/member identity determines the verdict, including prefixes,
combinators, alias chains, barrels, cascades, inheritance and captured getter
returns. Return annotations add candidate names for captured raw authorities;
nullable and inferred functions/fields/getters, mixin/extension/enum members,
record aggregates and bounded generic captures remain conservative. Erased
receivers with an unprovable storage operation fail INPUT2. Same-named local
classes/methods and the typed owner's reload callback are valid. Dynamic access
to a candidate persistence operation cannot establish provenance and returns
INPUT2. Dart leaves some omitted executable return annotations dynamic: only
an actual canonical resolved arrow expression or variable initializer's staticType
is inspected at an exposed/captured authored declaration. No control-flow or
cross-body type inference is performed; block/unknown erasure returns INPUT2.
Harmless inferred primitive arrows remain valid. This is not a whole-program
business-meaning or reflection detector.

SDK provenance, completed-class cardinality, namespace existence, actual part
ownership and unsupported conditional authored namespaces are checked before
candidate filtering. SDK namespace existence uses the configured analyzer's
actual SourceFactory, including embedder mappings such as Flutter's `dart:ui`;
all authored imported libraries preserve their actual package/file URI origin for
relative namespace resolution, rather than accepting only a matching physical
file. Part directives also resolve from the actual containing library origin;
their resolved physical source must agree with parsed part ownership. A physically
present file cannot make an unresolved package-relative part valid. No manually
maintained library allowlist is used. This tool depends on the pinned
analyzer's driver context solely for that URI mapping. Parts outside the parsed `lib/` scope, external authored
file namespaces and malformed ownership return INPUT2. Namespace branch support
requires a future explicit all-branch proof. Syntax errors are always INPUT2;
selected semantic errors are INPUT2 when a candidate requires resolution.
Ordinary errors in a library with no boundary candidate are the mandatory SDK
analyzer's responsibility: the fixture suite proves both the rule's clean verdict
and the actual SDK's rejection. A clean guard never means the Dart compiles.

Resolved analysis uses `tools/architecture/semantic_context.dart` and the pinned
analyzer 10.1 implementation's FileByteStore reader and validator with synchronous atomic summary writes. Generated summaries live
under `.dart_tool/architecture/profile-colours-view/`; checkout path, SDK
path/version/library metadata, package configuration and root analysis options
bind the namespace. Analyzer keys validate current source contents, dependency
signatures, language/features, options and summary-format version. Findings are
recomputed from current inputs; no clean/bad verdict is cached. The actual
configured analyzer SourceFactory and embedder mappings are unchanged. Missing
or corrupt bytes cause ordinary cache misses. Concurrent stores have distinct
process/isolate/sequence temporary suffixes. Cache deletion is safe. Empty-cache
first-use startup and warm-cache new-process feedback remain distinct acceptance
measurements; no warm result certifies a fast empty-cache start. The shared helper
also preserves the profiles guard's explicit-SDK/no-package-config contract;
this colour guard still requires its parsed package namespace configuration.
The prior 79 payloads remain unchanged; same-root fixtures additionally mutate
selected source, dependency types/existence, exports, parts, package origins, SDK
namespace visibility, root options, concurrent stores and corrupted summaries.
Package-origin part fixtures additionally prove missing namespace INPUT2 and a
valid adjacent part with actual source/fresh-AOT CLI checks.
The fixture supervisor retains its private scratch scope until the child VM
exits, then releases all fixtures. The shared store completes writes before
returning, so per-case recursive cleanup has no pending writer. Production cache files stay generated
under `.dart_tool`, independent of this test resource lifetime.

Run independently:

```sh
dart run tools/architecture/rules/profile_colours_view.dart --root . --json
dart run tools/architecture/tests/profile_colours_view_test.dart
dart compile exe tools/architecture/rules/profile_colours_view.dart -o build/profile-colours-view
dart run tools/architecture/tests/profile_colours_view_test.dart --compiled build/profile-colours-view
```

The CLI returns 0 for clean, 1 with stable rule/file/line diagnostics and 2 for
invalid scope, namespace, SDK or a semantic candidate. `--sdk PATH` explicitly
supplies a validated SDK, including standalone compiled fixtures. The host wrapper
`test/profile_colours_view_guard_test.dart` runs both the fixture proof and actual
production scan. Root owns mandatory CI/census integration and feedback acceptance;
no runtime budget is accepted by this initial correctness batch. Measure first
source/AOT startup and three warm processes on the same complete checkout/SDK
before rollout; retain hashes and measurements privately.

This guard supports the current ownership extraction, not storage/lifetime proof.
False-ACK restoration, retained confirmed display, FIFO admission, picker removal
and replacement, remove/re-add, admitted-operation settlement, failed reload,
shared observers and recovery affordances need public behavioral regressions.
See `profile_color_preferences_view_test.dart` and root's colour owner tests.
The business-to-theme import direction is enforced by the existing architecture
rules and is not duplicated here. No backend/protocol behavior is invented.
