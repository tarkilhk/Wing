# ARCH_USAGE_VIEW_DEPENDENCIES

The completed `UsageDashboard` library at
`lib/core/screens/administration/admin_usage_dashboard.dart` and its actual parts
must not import or export either raw namespace:

- `lib/core/services/administration_repository.dart`, including ProfileAdministration.
- `lib/core/services/usage_analytics.dart`, including UsageAnalyticsReader.

This independent command reuses the unchanged parsed namespace checker. It checks
normalized relative/package imports, prefixes, conditional branches, actual parts
and local barrel export closures. A declared namespace dependency remains forbidden
when show/hide is used. Importing the typed UsageAnalyticsSession whose own ordinary
imports include those adapters is valid: ordinary transitive imports are not followed.
Actual AnalyticsPage/profile composition stays outside the completed dashboard scope.
Same-spelling model libraries/classes and unrelated view members remain valid.

```sh
dart run tools/architecture/rules/usage_view_dependencies.dart --json
dart run tools/architecture/tests/usage_view_dependencies_test.dart
```

Exit 1 reports the exact declared directive dependency; exit 0 accepts; exit 2
fails closed for missing/ambiguous canonical scope, detached/missing actual parts
or malformed graph inputs. Six focused detector cases cover the original direct
adapter, reader barrel, actual part, required typed owner factory, unrelated model
homonym and missing part. Three actual CLI representatives assert exits 1/0/2
and exact id/file/line/subject/count. Accepted shared checker fixtures already
establish namespace robustness; no duplicate variants matrix is added.

The preserved original dashboard imports administration_repository.dart at line 4
and usage_analytics.dart at line 5. The successor imports its typed session.
Root owns original-source failure/current-source acceptance, CI registration and
focused execution; this author handoff contains no SDK or runtime jobs.

This guards the declared adapter boundary, not symbol dataflow, cache correctness,
protocol semantics, defensive copying or proof that every UI decision moved.
Period ordering, partial recovery, reentrant retirement and copied immutable facts
remain established through the owner controls and retained analytics tests.
Existing exact retirement protection can cover the removed raw field/helpers;
there is no blanket raw Map ban or new namespace resolver/framework.
