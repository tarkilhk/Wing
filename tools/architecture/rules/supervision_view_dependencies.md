# ARCH_SUPERVISION_VIEW_DEPENDENCIES

The canonical `ProfileSubagentPanel`, `ProfileGoalPanel` and
`ProfileBackgroundWorkPanel` libraries and actual parts may not expose the
canonical `lib/core/services/profile_workspace_controller.dart` namespace.
All three previously imported that raw coordinator and owned polling, criterion
captures or mutation feedback. They now borrow one captured
`ProfileSupervisionSession`, which issues criterion editors/reviews and detail
lifetimes. The controller remains the sole live roster/session-control/process
writer and physical execution authority. The session's private imports are valid.

This uses unchanged `checkViewAdapterDependencies`: direct imports/exports,
local export closure, conditional alternatives, normalized package/relative
paths and actual parts are validated. Prefixes/combinators do not waive the
boundary. Ordinary transitive imports are not traversed. Library-bound unrelated
homonyms are valid. Unsupported/missing/ambiguous inputs produce `ARCH_INPUT`
and exit 2; canonical dependencies produce this diagnostic and exit 1; clean
input exits 0. This is a finite namespace property, not a ban on controller
spelling or all locally reimplemented business logic.

```sh
dart run tools/architecture/rules/supervision_view_dependencies.dart --json
dart run tools/architecture/tests/supervision_view_dependencies_test.dart
flutter test test/supervision_view_dependency_guard_test.dart
```

Eight focused detector cases bind all three original imports, a prefixed barrel,
a real part, the typed owner, a same-name unrelated library and missing input.
Three exact CLI representatives retain identity/location, clean output and
`ARCH_INPUT` assertions with an explicit completeness check. The shared helper's
existing namespace fixtures cover its broader indirections; no new helper or
resolver is added.

Standard required-argument analysis protects omission of the captured
`canDispatch` predicate at actual controller callers. It cannot prove that a
predicate is correct or establish disposal, held-ACK ordering, exact criterion
capture, tail retry cadence or deeply immutable returned facts. Existing
`profile_goal_panel_test`, `profile_subagent_panel_test`,
`profile_background_work_panel_test`, `profile_session_control_test`,
`profile_subagents_test` and `profile_background_work_test` remain behavioral
controls. Admitted commands may settle; route closure revokes subsequent sends
and local publication. Root owns original/current production CLI proof,
source/compiled fixture execution, CI/root registration and host/render checks.
This source-only handoff reports no executed proof or feedback timing.
