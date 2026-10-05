# ARCH_CONNECTOR_DETAIL_MOUNT

The actual nested connector picker regression mounted AdminConnectorDetail while
the underlying list was building. Its initState called `_load()` synchronously;
the shared inventory refreshed and notified that list during build. The repaired
initial read runs in `WidgetsBinding.instance.addPostFrameCallback` and checks
mounted plus captured route/session identity before reading. The existing nested
picker test detects the original during-build notification; no new widget test
or hypothetical callback problem motivates this rule.

This finite AST rule inspects only `_AdminConnectorDetailState.initState` in
`lib/core/screens/administration/admin_connectors_page.dart`. Calls to `_load`
with implicit/this receiver or `refresh` on `_session`/captured `session` must
belong to the first inline function argument of the actual spelled
`WidgetsBinding.instance.addPostFrameCallback` invocation. An arbitrary closure
is not accepted as deferral. The closest function-expression ancestor must be
that callback, so nested unrelated closures do not receive an exemption.

This guards the encountered initialization pattern, not every initState or
notification. It does not resolve SDK symbol shadowing, renamed helpers,
delegated reads, arbitrary aliases or async dataflow. Ordinary analysis validates
the SDK names; the existing picker/lifetime controls verify actual mounted,
captured identity and notification behavior. Changing this finite owner seam
requires reviewing the contract rather than silently dropping its scope.

Missing/ambiguous canonical class, method or block body and unsupported part
scope fail with exit 2. Unsafe calls produce findings and exit 1; valid exit 0.
Three fixtures cover original direct read, current post-frame read and missing
method; each also invokes its corresponding CLI exit 1/0/2.

```sh
dart run tools/architecture/rules/connector_detail_mount.dart --json
dart run tools/architecture/tests/connector_detail_mount_test.dart
```

Root owns CI integration, focused execution and original/successor proof. This
source handoff claims no executed SDK/runtime proof or timing measurement.
