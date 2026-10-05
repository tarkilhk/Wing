# Canonical workspace observations

ARCH_WORKSPACE_CANONICAL_STATE examines the three actual canonical owners in
profile_workspace_controller.dart and its declared parts. Required observations
are getters; public writable fields, mutable bags and setters are forbidden.
Only the finite genuine composition fields are admitted. Unsupported ancestry,
missing observations and missing parts fail with INPUT rather than a clean result.
Discovery must borrow retained instance storage, avoiding allocation on every read.
The rule does not infer arbitrary getter purity or asynchronous lifetime behavior.

Run `dart run tools/architecture/rules/workspace_canonical_state.dart`. Ten
independent declaration fixtures exercise valid readonly facts/explicit storage,
writable fields/bags/setters, allocated discovery, ancestry/shadow aliases, missing
observations/parts and CLI exit0/1/2. Run
`dart run tools/architecture/tests/workspace_canonical_state_test.dart`.
Workspace commands and existing crossing-sequence controls protect real generation,
identity, journal, admission and disposal behavior beyond this static boundary.
