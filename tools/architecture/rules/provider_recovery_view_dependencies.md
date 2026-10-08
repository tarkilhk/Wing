# ARCH_PROVIDER_RECOVERY_VIEW_DEPENDENCIES

The completed `lib/core/screens/administration/admin_provider_detail.dart`
library (detail, instructions, and file review plus actual declared parts) must
not directly import/export canonical `administration_repository.dart` or
`profile_gateway.dart`, including local export barrels and conditional namespaces.
Original detail imported AdministrationRepository and interpreted raw provider
flow/source/disconnect metadata while coordinating mutations in State fields.
Use required ProviderRecovery factories and immutable typed facts; captured route
composition remains in provider_access_navigation.dart.

Run independently:

```sh
dart run tools/architecture/rules/provider_recovery_view_dependencies.dart --strict --json
dart run tools/architecture/tests/provider_recovery_view_dependencies_test.dart
```

The existing unchanged declared-namespace checker supplies normalized package/
relative/conditional/part identities. Ordinary transitive imports are not walked:
a typed owner importing its repository is valid. show/hide does not waive a
library dependency. Scope missing/ambiguous or an undeclared part exits2;
violations exit1; valid input exits0. The six focused fixtures retain actual
adapter, barrel, part, typed-owner, homonym and missing-part cases plus three CLI
representatives. Existing capabilities fixtures test the shared algorithm.

This protects declared adapter dependencies, not arbitrary business dataflow,
readonly observation semantics, lifetime or dispatch ordering. The retained
provider recovery screen/owner and real console controls establish those
behavioral contracts. No new resolver, cache, callback matrix or timing gate.
Root owns CI registration, source RED/GREEN execution and measured ordinary
runtime; this source-only handoff claims no executed checks.
