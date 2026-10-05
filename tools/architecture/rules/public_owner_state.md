# Completed owner observation declarations

`ARCH_PUBLIC_OWNER_STATE` prevents public writers returning to these exact
library/class surfaces:

| Library under `lib/core/services/` | Class | Protected observations |
| --- | --- | --- |
| `scheduled_tasks_controller.dart` | `ScheduledTasksController` | tasks, loading, error, notice, checkedAt, busy, uncertain |
| `administration_health_session.dart` | `AdministrationHealthSession` | overviews, persistenceError |
| `administration_overview.dart` | `AdministrationOverview` | observations, connectorChecks |
| `administration_overview.dart` | `AdministrationObservation` | data, checkedAt, error, loading |

The three command owners expose instance getters; their backing fields remain
private. A public field, including a final public collection field, violates
that completed interface. The immutable observation value captures final
instance fields without setters. An uninitialized `late final` field still has
a public write slot and violates the property. Initialized late-final fields
have no public setter and remain valid. Grouped declarations are checked for
each protected field. Explicit setters fail even beside a valid getter.

The symptom was a second writer to authoritative task/Health observations.
The remedy is private command-owned state with passive getters, or final captured
value fields. The fallback alias defect is complementary: returning immutable
catalog and picker-choice lists needs behavioral prevention, even when the
list field itself is final.

The rule parses only the three known owner libraries. A finding requires the
exact declared class in its canonical library; unrelated classes, labels and
homonyms in other libraries do not match. No symbol resolver, package lookup or
source-result cache is used. All expected protected members must be present.
A missing/duplicate expected class, missing property, static member posing as
instance state, syntax error or missing file is input exit 2 rather than a clean
proof. Unknown superclass, mixin or implemented-interface ancestry also returns
input 2. Current command owners' direct `ChangeNotifier` ancestry is admitted
through its explicit `package:flutter/foundation.dart` import, honoring prefix,
show/hide and local type shadowing. The value has no superclass clause. Parts
and conditional namespaces are unsupported input 2, so moving declarations into
an uninspected unit cannot silently pass. Extending this finite scope requires
review rather than a suppression.

This declaration check does **not** establish that getter results or nested
collections are immutable, that input maps/lists were defensively copied, or
that notifications, ACKs, cancellation and persistence have the correct order.
The existing `scheduled_tasks_controller_test.dart`,
`administration_health_session_test.dart`, `administration_overview_test.dart`
and `profile_fallback_edit_session_test.dart` retain those behavioral guards.
It does not typecheck arbitrary source bodies or prove all transitive import
namespaces; mandatory standard Dart/Flutter analysis remains responsible for
language validity and framework import resolution.

```sh
dart run tools/architecture/rules/public_owner_state.dart
dart run tools/architecture/tests/public_owner_state_test.dart
```

The standalone CLI accepts only optional `--root PATH`. Findings include stable
ID, owner/member and source line; exits are 1 (violation), 0 (complete finite
surface passes), and 2 (unsupported/invalid input). The fixture runner checks
invalid, legitimate nearby, missing/static/grouped/setter/ancestry/part inputs,
plus actual source CLI 1/0/2. No compilation or timing job is required for this
functional proof. Parent-owned CI registration and any feedback acceptance remain
separate; no local speed or deep-freeze claim follows from these results.
