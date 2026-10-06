# Intelligence read admission

`ARCH_INTELLIGENCE_READ_ADMISSION` protects one finite boundary:
`ProfileWorkspaceController.loadIntelligence` in its actual Dart library,
including declared parts. An awaited read must be one direct awaited local
initializer or a bare await that discards the result, with a
synchronous owner-local `requireCurrentRead` callback declared and invoked before
the first I/O statement, then invoked directly after each awaited statement before processing the
result. A delayed check, an uninvoked closure or an asynchronous checker does not
meet this contract. Unrelated classes and libraries with the same names are valid.

```sh
dart run tools/architecture/rules/intelligence_read_admission.dart --strict
flutter test --no-pub test/intelligence_read_admission_guard_test.dart test/profile_intelligence_test.dart
```

The actual defect was a held `config.get` completion overwriting reasoning after
the same retained chat reconnected and hydrated a newer runtime. The existing
owner now captures resource, durable key, runtime identity, read generation and
intelligence revision. Hydration, newer reads and configuration writes invalidate
older reads. Admission runs before any field mutation or notification.

The linter checks placement and synchronous invocation, not the semantic content
of the callback. Static syntax cannot establish which held response owns facts
after reconnect or hydration. The controlled regressions in
`test/profile_intelligence_test.dart` establish those event-order properties.
Changes to the admission callback require those regressions; a structurally
present but incorrect callback is not certified by this linter.

Invalid/valid fixtures in `test/intelligence_read_admission_guard_test.dart`
exercise the original omission, missing/late/nested/async checks, actual parts
and unrelated homonyms. Its CLI fixtures require nonzero rejection and successful
valid input; malformed boundary input exits 2. Both PR and release workflows run
the independent linter, and the required-quality-gate guard prevents omission or
soft failure. Standard host tests execute its fixture file.

This uses the existing parsed snapshot and CLI, with no new resolver or framework.
Local feedback budgets are 15 seconds for a source CLI and 1 second for a compiled
CLI on the established host/toolchain. Timing evidence is private; timing does
not change the deterministic correctness result. Investigate an exceeded budget
instead of raising it silently.
