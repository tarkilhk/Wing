# ARCH_LOGS_VIEW_DEPENDENCIES

The completed `lib/core/screens/administration/admin_logs_page.dart` library
and its actual parts must not import or export a namespace exposing either
canonical raw adapter: `lib/core/services/administration_repository.dart` or
`lib/core/services/profile_gateway.dart`. The original view directly captured
the repository, constructed log queries and decoded mutable wire maps. The
typed Logs owner now captures the server and owns query, decoding and reads;
the view renders observations and forwards filter/refresh intent.

This independent command configures the unchanged
`tools/architecture/view_adapter_dependencies.dart` checker with the actual
`AdminLogsPage` marker and canonical library paths. It follows direct
imports/exports, local export closure, conditional alternatives, normalized
relative/package paths and actual parts. Prefixes and `show`/`hide` do not waive
the declared dependency. Typed owners may import the adapters internally;
ordinary transitive imports are not traversed. Unrelated homonymous libraries
and members remain valid. Parent/runtime captured-server factory composition is
outside this completed library; it receives no blanket feature exemption.

Missing/ambiguous scope, roles, actual parts or visible authored namespaces fail
with exit 2. Findings exit 1; valid input exits 0.

```sh
dart run tools/architecture/rules/logs_view_dependencies.dart --json
dart run tools/architecture/tests/logs_view_dependencies_test.dart
```

Six focused cases cover the original direct repository import, an exported
gateway namespace, an actual part, a typed owner/model with legitimate separate
composition, unrelated homonyms and missing-part input. Only invalid original,
typed valid and input-error cases also invoke the CLI, proving exits 1/0/2.
Accepted capabilities fixtures retain the shared algorithm's wider namespace
evidence; this adds no resolver, framework or repeated variants matrix.

This guards a declared library boundary, not arbitrary symbol dataflow or all
business semantics. Captured-server reads, stale filter results, read failures
and retirement remain behavioral responsibilities. Renamed adapter paths or
unsupported package aliases need an explicit contract update. Root owns
production original/successor proof, CI wiring and focused execution; this
source handoff claims no executed proof or timing measurement.
