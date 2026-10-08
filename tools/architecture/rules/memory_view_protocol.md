# Memory views receive typed readings

`ARCH_MEMORY_VIEW_PROTOCOL` independently checks `lib/core/screens/administration/admin_memory_page.dart` and its actual parts. It prevents resolved protocol calls/capability references and canonical memory wire/identity parsing from returning to the completed list/detail view. Candidate names are selected cheaply with parsed AST. Findings require analyzer-resolved provenance from `ProfileAdministration`, `AdministrationRepository`, `DashboardClient`, canonical `RetainedMemory*` value factories, `administrationRows`, `dart:convert.jsonDecode`, or `dart:core.int.tryParse`. Prefixes, aliases, barrels, inherited members, cascades, declaration/consumer parts and factory tear-offs are covered. Passive typed identity reads and unrelated same-named constructors/methods are valid. Unresolved/dynamic candidate operations and candidate libraries with local conditional provenance fail as input errors rather than claiming an all-platform proof.

```sh
dart run tools/architecture/rules/memory_view_protocol.dart --root . --json
dart run tools/architecture/tests/memory_view_protocol_test.dart
dart run tools/architecture/tests/retained_memory_values_test.dart
```

SDK selection uses the shared validated `tools/architecture/dart_sdk.dart` helper, including explicit `--sdk PATH` for compiled binaries outside the checkout. A supplied invalid SDK fails even when no candidate requires resolution. The optional fixture runner `--compiled PATH` proves compiled bad/valid/input exits and exact diagnostic locations alongside the interpreted standalone command.

The standalone guard returns 0 for valid, 1 for violations, and 2 for invalid/unverifiable input. Fixtures prove actual CLI exits 1/0/2, stable diagnostic ID/file/line, valid nearby symbols and indirection. The host wrappers have two-minute correctness watchdogs. Warm compiled full-checkout feedback target is one second; interpreted startup target is fifteen seconds, subject to measured acceptance on the current checkout. Keep actual measurements/executables under ignored `build/`, not public Git. This finite rule does not claim to identify every invented wire parser.

Old positional ID reconstruction through the canonical factory is forbidden in the view. The typed `AdminMemoryDetail.identity` interface and standard analyzer reject raw string navigation arguments. Correct graph-node/card matching requires data and is protected behaviorally, not by regex over source or an interpolation spelling check.

## Current stock and capabilities

Inspected official upstream `5d3c05977bb3c8b7cfd6b3e39d96f6e35a9e0662`:

- `hermes_cli/web_routers/status.py:671`: graph GET scopes the complete learning graph to the explicit profile.
- `agent/learning_graph.py:156`: supplied memory node IDs are `memory:<source>:<global-card-index>:<12-lowercase-hex-fingerprint>`. Sources are exactly `memory` and `profile`; the ordinal counts the combined card list, not a filtered list or per-source list.
- `agent/learning_graph.py:161`: card fields `source`, `title`, `body`, `fingerprint`; `body` is only a preview, so its hash cannot reconstruct the full-memory fingerprint.
- `agent/learning_graph.py:237`: corresponding nodes supply `id`, `label`, `kind:memory`, `memorySource`.
- `hermes_cli/web_routers/status.py:698` and `agent/learning_mutations.py:145`: scoped node GET returns `ok:true`, `kind:memory`, exact submitted `id`, `label`, full `content`. A disappeared/stale identity is an HTTP error.

Wing retains its read/copy-only memory capabilities. Current upstream mutation routes are intentionally unused. No compatibility positional ID reader, filesystem source alias, missing-field default or mutation fallback is implemented. UI copy identifies Wing's read-only view without falsely claiming that current upstream lacks mutations.

The canonical minimal reading fixture is:

```json
{
  "memory": [{"source":"memory","title":"First memory","body":"First preview","fingerprint":"111111111111"}],
  "nodes": [{"id":"memory:memory:0:111111111111","label":"First memory","kind":"memory","memorySource":"memory"}]
}
```

The graph and each used memory card/node require the fields shown. Other stock graph fields (`edges`, `clusters`, `stats`), skill nodes, timestamps and unrelated node metadata are not retained by this projection. Memory identity/source/ordinal/fingerprint/title correspondence must be unambiguous; missing/duplicate nodes fail closed. Details require `ok`, `kind`, `id`, `label` and `content` with current types. Detail identity is checked against the captured supplied graph identity. The projection never recalculates a usable identity from an array position or preview body.

## Regression ownership

`RetainedMemoryCatalogSession` owns search, current reading projection, parsing, refresh generations, read failure/recovery and the captured profile lease. `RetainedMemoryDetailSession` owns the exact captured identity and the same read lifetime rules. Shared read mechanics remain private; neither owner exposes a write command or stores a runtime cache. A malformed refresh is parsed before replacing the prior reading; error, last checked and search are retained. Each in-flight read drains a captured lease after route retirement, without notification or further requests from the retired route. Newer reads supersede held older completions.

Public regressions are `test/retained_memory_view_test.dart` (filtered navigation uses the exact fingerprinted graph ID; malformed refresh retains visible reading/search), `test/retained_memory_session_test.dart` (scope, deep values, held completion, generations, read-only recovery, exact detail identity and retirement), and the pure `tools/architecture/tests/retained_memory_values_test.dart`. `test/retained_memory_values_guard_test.dart` and `test/memory_view_protocol_guard_test.dart` run the independent public commands in the host suite. These guards do not prove backend atomicity or device appearance/performance; actual Studio and device acceptance remain separate.

Bare inherited getter/method capability capture is also selected and requires canonical resolved declaration provenance. A same-named local parameter/reference is accepted; fixtures protect both cases.

`test/memory_view_protocol_guard_test.dart` enforces both the actual complete-scope production CLI and the independent fixture runner in the full host test gate. Fixture success alone is not a production scan; a clean no-candidate production scan alone is not resolver correctness.
