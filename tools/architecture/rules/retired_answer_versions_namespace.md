# ARCH_RETIRED_ANSWER_VERSIONS_NAMESPACE

The workspace still enumerated preferences and removed keys beginning with
`answer_versions_v1_`, even after the answer-version feature and all of its
producers were retired. That obsolete cleanup and its legacy namespace are now
removed. The requested target has no backward-compatibility cleanup.

This independent parsed rule rejects string literal values beginning with the
exact retired prefix in the containing library rooted at
`lib/core/services/profile_workspace_controller.dart`, including its real
reciprocal URI parts. It checks ordinary/raw/escaped literals, decoded constant
adjacent literals, and literal fragments inside interpolation. An adjacent
constant string produces one finding even if its children independently contain
the complete prefix. Interpolation expressions are still traversed for independent
retired literals. Comments and different library files remain valid. Current
`workspace_reading_v1_` and differently prefixed namespaces remain valid.

The containing file must exist and be a library. Part paths must resolve uniquely,
exist, reciprocate the owner, and have no nested/named/orphan ownership. Unsupported
part graphs or malformed source fail input rather than silently skipping a moved
literal. There is no class/member-binding inference: the finite property forbids
the retired literal namespace inside this exact owner library, independent of
local variable spelling. It does not evaluate arbitrary binary concatenation,
constant aliases, imported values, reflection or runtime-computed keys. It does
not prove preference deletion, retained history or universal dead-code freedom.
The ordinary compiler and existing owner/reading behavior tests retain those
independent responsibilities; no behavioral duplicate is added here.

Clean input exits 0. Findings use `ARCH_RETIRED_ANSWER_VERSIONS_NAMESPACE`, physical
file/line and the exact prefix subject, then exit 1. Missing/unsupported/malformed
source input exits 2 with `[ARCH_INPUT]`. No baseline is allowed. Twenty-three
parsed fixtures include the original cleanup, repaired reading namespace,
interpolation/adjacent/escaped/raw values, comments/unrelated sources, moved
literal parts and unsupported graph/input. Three real CLI representatives prove
1/0/2 when Root executes the fixture host.

```sh
dart run tools/architecture/rules/retired_answer_versions_namespace.dart --json
dart run tools/architecture/tests/retired_answer_versions_namespace_test.dart
flutter test --no-pub test/retired_answer_versions_namespace_guard_test.dart
```

Both quality workflows require the independent production rule and fixture CLI
as hard-failing commands. Existing required-quality-gate fixtures test omission,
substitution, ignored failures and conditional bypass for both commands. Root
unions the exact new executable roots into the current census manifest.
The rule reuses Snapshot/Finding/CLI and adds no dependency or framework. SDK
execution and informational timing remain pending Root validation.
