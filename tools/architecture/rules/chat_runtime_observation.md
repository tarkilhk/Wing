# Passive runtime observation boundary

`ARCH_CHAT_RUNTIME_OBSERVATION` protects the completed runtime declaration
boundary in the canonical `ProfileChat` class in
`lib/core/services/profile_workspace_controller.dart`. The original class held
writable runtime facts (`runtimeId`, `status`, prompt/approval fields and a public
tool activity list). The repaired class keeps a private final canonical
`ChatRuntime` and exposes a nonnullable canonical `ChatRuntimeObservation` getter.
The existing retirement rule separately protects removed declarations and
forwarding getters; this rule does not duplicate that list.

The three fact classes in `lib/core/models/chat_runtime.dart` retain their finite
stored fields, final instance declarations, and no public setters. Uninitialized
late-final fields have write slots and fail. Computed read-only getters and
unrelated mutable objects remain valid. Unknown fact or ProfileChat ancestry,
missing canonical files/classes/stored facts or an unsupported private runtime
surface return input exit 2. A present ProfileChat lacking the passive getter
violates the boundary (exit 1). The runtime service's `ChatRuntime` declaration must exist.

The existing analyzer context/SDK helpers are reused unchanged. Resolved Dart
types establish library identity, accepting canonical aliases, prefixes and
reexports while rejecting nullable or same-named foreign types. Controller parts
are resolved with their containing library; duplicate ProfileChat declarations
fail input. Conditional namespaces in canonical inputs are unsupported. Standard
Dart/Flutter analysis still validates source bodies and transitive namespaces.
This check resolves only the known owner library and its dependencies, without a
new framework or rule-result cache.

```sh
dart run tools/architecture/rules/chat_runtime_observation.dart
dart run tools/architecture/tests/chat_runtime_observation_test.dart
flutter test test/chat_runtime_observation_guard_test.dart
```

The independent CLI accepts `--root PATH` and `--sdk PATH`. Exits are 0 (finite
surface passes), 1 (violation) and 2 (unsupported/invalid input), with stable rule
ID, canonical file, declaration line and class/member subject. Fixtures include
valid/unrelated declarations, mutable facts/owner, setters, grouped stored
surface, wrong canonical types, aliases/reexports and missing authorities. The
fixture runner invokes the actual source CLI for 0/1/2.

To demonstrate the actual original production defect without reverting the
checkout, run the fixture command with
`--original /tmp/wing-chat-runtime-original-source-freeze`. It copies the exact
original controller into a temporary fixture with successor model/runtime
authorities; the original ProfileChat lacking a passive getter must produce this
rule's violation. This overlay avoids mistaking the original missing successor
model for proof of the defect. Production acceptance is the host test above or
the CLI against the successor checkout. No source or SDK jobs were executed by
the source author; parent integration owns format, CLI proof, timing and CI wiring.

This guard does not prove defensive copies, nested value immutability, collection
mutation/dataflow, secret lifetimes or async order. The exposed `toolActivities`
`Iterable` and standard compiler reject `removeWhere` misuse. Controlled runtime
behavior tests retain execution, recovery, pending-input and stale-completion
contracts. Static success does not close those obligations.
