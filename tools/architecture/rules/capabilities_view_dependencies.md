# ARCH_CAPABILITIES_VIEW_DEPENDENCIES

The completed `lib/core/screens/profile_capabilities_screen.dart` library and its
actual parts must not declare an import or export exposing either canonical raw
adapter: `lib/core/services/profile_gateway.dart` or
`lib/core/services/administration_repository.dart`.

This small parsed-graph rule follows local **exports only** from each direct
namespace dependency. A typed session that imports an adapter internally is
valid. Relative and `package:wing/` paths, dot segments, prefixes, deferred
imports, export cycles and every conditional import/export branch are checked.
`show`/`hide` does not waive a declared raw-adapter dependency. Unrelated symbols
with the same spelling and same-named libraries at other paths are valid.

Missing or ambiguous completed scope, mismatched declared roles, malformed or
missing actual parts, and missing visible authored namespace targets return
input exit 2. Actual URI and named `part of` ownership are checked. Parts share
their containing library's namespace: the completed class may live in a part,
while diagnostics locate the containing import. The shared parser rejects
malformed import/export declarations inside parts as input exit 2.

```sh
dart run tools/architecture/rules/capabilities_view_dependencies.dart --json
dart run tools/architecture/tests/capabilities_view_dependencies_test.dart
```

The independent CLI reuses the shared snapshot/CLI and forces strict mode:
violations exit 1, valid input exits 0, malformed input exits 2 (`ARCH_INPUT`).
All detector fixtures run in process. Only one representative of each exit is
also invoked through the source CLI; no repeated per-fixture SDK launches occur.
There is no resolver, cache, network, runtime timing assertion or compilation.

This guards **declared library dependencies**, not symbol dataflow, arbitrary
business logic, dynamically supplied callbacks or runtime ordering. External
packages and SDK namespaces are outside this finite canonical-adapter property;
their low-level restrictions remain enforced by existing architecture rules.
Alternate package aliases not represented by the shared snapshot are outside
this contract. Required production scope, CI integration, measured feedback
budget and behavior regressions remain separate acceptance obligations; no
performance measurement or production acceptance is claimed by this source.
