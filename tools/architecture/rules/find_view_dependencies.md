# ARCH_FIND_VIEW_DEPENDENCIES

The completed `lib/core/widgets/chat_find_sheet.dart` library and its actual
parts must not import or export a namespace exposing either canonical raw
history/workspace adapter: `lib/core/services/profile_gateway.dart` or
`lib/core/services/profile_workspace_controller.dart`. The original Find view
imported raw history pages and owned collection, paging/retry, deduplication and
search projection. `ChatReadingSession` now owns those responsibilities and
publishes immutable issued matches; the workspace owner captures actual history
and installs the selected reading window.

This independent command configures the unchanged
`tools/architecture/view_adapter_dependencies.dart` checker. It follows direct
imports/exports and local export closure, all conditional alternatives,
normalized relative/package paths and actual parts. A prefix or `show`/`hide`
does not waive the declared dependency. Typed owners may import the adapters
internally; ordinary transitive imports are not traversed. Unrelated homonymous
libraries, members and external namespaces remain valid.

Missing/ambiguous scope, roles, actual parts or visible authored namespaces fail
with exit 2. Findings exit 1; valid input exits 0. The existing retirement guard
also protects 19 exact removed Find and workspace-view identities. It permits
the controller's active `backToLatest` command, typed observations and
presentation query controls, expansion state and navigation.

```sh
dart run tools/architecture/rules/find_view_dependencies.dart --json
dart run tools/architecture/tests/find_view_dependencies_test.dart
flutter test test/retired_declarations_guard_test.dart
```

Six focused cases cover the original direct gateway dependency, a local barrel
exposing the workspace adapter, an actual part, a typed owner/model, unrelated
homonyms and missing-part input. Only the original invalid, typed valid and
missing-part cases additionally run the CLI, proving exits 1/0/2. The accepted
capabilities fixtures retain the shared namespace robustness.

This guards a declared library boundary, not arbitrary callbacks, symbol
dataflow, nested immutability or all business semantics. Exact retirement
identities cannot detect renamed view policy. Captured read authority, stale
selection rejection, reentrant retirement and temporary focus lifetime need
the public controller regressions in `test/profile_saved_history_test.dart`
and retained Find/large-chat UI regressions. Transcript grouping, ordinary
history and output workflows remain separately scoped. A renamed canonical
adapter or unsupported package alias needs an explicit contract update. No
resolver, cache, compilation or timing framework is added. Production proof,
CI integration and focused execution are Root-owned; this source handoff claims
no executed proof.

The retirement manifest also records the first migration's incorrect
`ProfileChat._readingWindow` field: per-chat temporary pages could survive when
only the last rendered focus was released. A single controller-owned active
window remains legitimate. The declaration fixture distinguishes these exact
owners; the public A-to-B-to-A/focus-release regression must protect the same
semantic mistake if renamed. This is not a cache-size or callback heuristic.
