# Browser row work

`ARCH_BROWSER_ROW_WORK` prevents the canonical
`ProfileWorkspaceController.browserResource` member from being referenced or
captured in the canonical `ChatBrowserData._refreshRow` body, including its nested
callbacks. Keep connection-wide index access outside row refresh; observe an
already retained runtime with the captured session key instead.

The selected library is `lib/core/services/chat_browser_data.dart`; the member's
owner is `lib/core/services/profile_workspace_controller.dart`. Actual resolved
library, class and member identity decides findings. Receiver/import/type aliases,
prefixes, exports, cascades, inherited members, tear-offs and statically initialized
local/field/top-level alias chains are checked. Instance and top-level getter
aliases, including block bodies, are followed. A non-callable retained result
initialized outside the row is valid. Unrelated homonyms, comments, labels and
index access in other methods are valid. Parts use their real containing library, including authored
parts outside `lib/`.

SDK, authored namespace existence/provenance, syntax and part ownership are
checked using the configured analyzer SourceFactory, preserving file/package URI
origins and SDK embedder mappings, before the parsed candidate filter. Conditional authored namespaces fail with
INPUT until all branches can be proven. Installed package contents remain
analyzer-owned. If a possible member or initializer alias is used, the standard
analyzer resolves candidates (enabling the pinned SDK's private named parameter
feature only through an in-memory options overlay); semantic errors and
unknown/dynamic accessor candidates fail with INPUT. The clean path avoids resolution. Ordinary semantic
errors with no candidate still belong to the mandatory Dart/Flutter analysis
gate: this linter does not replace that gate.

This finite structural property does not prove constant runtime cost, absence of
all index work, arbitrary supplied callback behavior, mutable alias assignments
outside the body, or interprocedural helper costs. The unchanged personal/work
streaming cases in `test/chat_list_target_test.dart` also assert zero connection
index reads and zero list rebuilds. Those behavioral assertions remain necessary.

Run from the app root:

```sh
dart run tools/architecture/rules/browser_row_work.dart --root .
dart run tools/architecture/tests/browser_row_work_test.dart
```

The rule accepts `--sdk PATH` for an explicit validated SDK. Exit codes are 0
(clean), 1 (stable scoped findings), and 2 (invalid/unsupported input). Fixtures
exercise public checks and real source/fresh-AOT CLI1/0/2, including compiled SDK
discovery, invalid SDK rejection before filtering, and explicit SDK without a
package configuration. Production and fixtures also run through
`test/browser_row_work_guard_test.dart`. Root-owned CI registration and quiet
feedback acceptance are separate gates; no runtime budget is claimed here.
