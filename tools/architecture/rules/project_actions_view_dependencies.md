# ARCH_PROJECT_ACTIONS_VIEW_DEPENDENCIES

The canonical completed view library `lib/core/screens/profile_project_actions.dart` and its actual parts must not declare a dependency on `profile_gateway.dart` or `profile_workspace_controller.dart`. The original view directly decoded raw rows and constructed/captured workspace mutations. Use `ChatBrowserData` and its issued typed action owner instead.

Run `dart run tools/architecture/rules/project_actions_view_dependencies.dart --root . --roles tools/architecture/roles.json --json`. Fixtures: `dart run tools/architecture/tests/project_actions_view_dependencies_test.dart`. Exits are 0 accepted, 1 declared dependency, 2 invalid/ambiguous input. Root integrates this command into CI.

This uses the unchanged accepted namespace checker: normalized relative/package and conditional namespaces, actual containing libraries/parts, and local barrel EXPORT closure. Ordinary imports inside the typed owner are valid. Show/hide does not waive a declared raw dependency. It does not establish symbol dataflow, callback timing, runtime lifetime or every UI policy; retained behavioral controls and normal analysis cover those.
