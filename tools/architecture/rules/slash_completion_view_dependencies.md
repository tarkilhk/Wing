# ARCH_SLASH_COMPLETION_VIEW_DEPENDENCIES

The completed `lib/core/widgets/slash_command_suggestions.dart` library and
actual parts must not expose the canonical raw workspace controller namespace
`lib/core/services/profile_workspace_controller.dart`. The original widget
loaded the catalog, selected completion strategy, decoded wire items and
converted Python code-point offsets into Flutter UTF-16 offsets. The existing
controller completion command and pure immutable `SlashCompletion` now own
those decisions. Suggestions require typed `loadCompletion(query)` and
`saveDraft(text)` callbacks; the real workspace captures its exact chat and
controller when composing them. Debounce, popup, cursor extraction, rendering
and request-generation suppression remain in the widget. No owner or cache is
added. Selection of an issued item and exact-query insertion belong to the
pure model; persistence remains the existing composer/controller command.

This command configures unchanged `checkViewAdapterDependencies`: direct
imports/exports, local export closure, all conditional alternatives, normalized
relative/package paths and actual parts. Prefixes and show/hide do not waive
the declared dependency. Unrelated library/member homonyms are valid. Missing
or ambiguous scope, roles, parts or visible authored namespace fail closed
with `ARCH_INPUT`/exit 2. Findings exit 1; clean input exits 0. Six small cases
cover the original import, barrel, actual part, typed callbacks, homonyms and
missing part. Three source CLI representatives assert exact outputs/locations
and completeness of exits 1/0/2; existing shared-helper fixtures own the
broader namespace contract. No helper, resolver or framework is added.

```sh
dart run tools/architecture/rules/slash_completion_view_dependencies.dart --json
dart run tools/architecture/tests/slash_completion_view_dependencies_test.dart
flutter test test/slash_completion_view_dependency_guard_test.dart
```

Current stock Hermes commit `1fd75357e92d217199e04849b819e7de10f35e1d`
[`methods_complete.py`](https://github.com/NousResearch/hermes-agent/blob/1fd75357e92d217199e04849b819e7de10f35e1d/tui_gateway/methods_complete.py)
uses Python string indices for `replace_from`, and binds `session_id` to the
owning profile/workspace. The current
[result contract](https://github.com/NousResearch/hermes-agent/blob/1fd75357e92d217199e04849b819e7de10f35e1d/tui_gateway/contracts/profiles_vault_complete_foreign_subagents.py)
provides string text/meta items. Wing preserves its existing catalog strategy,
exact query, suffix and category behavior; the typed result validates and
converts the stock range and copies immutable items. No backend or format
compatibility is introduced.

This guards a declared namespace, not arbitrary renamed business policy,
callback provenance or temporal freshness. Existing slash controls retain
late-result suppression, profile-scoped requests, insertion without sending,
warning reachability and saved draft roundtrip. The added pure value control
protects Unicode range conversion, immutable retained items and obsolete query
selection. Runtime/record freshness remains enforced by the captured existing
controller; this rule does not prove asynchronous authority. Root owns actual
original1/current0, fixture execution and CI/root integration. This source-only
handoff reports no executed proof or timing acceptance.
