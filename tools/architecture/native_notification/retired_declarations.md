# Two retired native declarations

`NATIVE_RETIRED_DECLARATION` protects a finite original-backed subtraction:

- `BackgroundMonitoringService.summaryId` was the constant `214602`, consumed
  only by two cancellation calls. No current authored producer posts this fixed
  ID. The actual foreground service owns `214601`.
- `NotificationHandleStore.random` was an optional primary-constructor function
  property. Production and all existing JVM constructors used its UUID default;
  none supplied the option. `issue` now calls the same UUID generator directly.
  Its clock input remains live in expiry tests.

The independent Kotlin PSI rule has an explicit two-row retirement table. It
parses the two canonical files and requires their package and unique top-level
class owners before reporting findings. It rejects the service's own `summaryId`
property, including a companion member or primary-constructor property; and the
handle store's primary-constructor `random` parameter, with or without `val/var`.
Visibility, ordinary/backtick identifiers and named companions do not hide those
declarations. Local variables, helper-function parameters, nested or unrelated
classes, comments and display strings are valid. The live `now` clock and current
UUID call are valid. A body property named `random` is outside the retired
constructor-option contract and remains valid.

This guards declaration resurrection. It does not infer deadness or prove
notification ownership, UUID unpredictability, lifecycle, expiry, cancellation or
thread safety. Renamed members, secondary-constructor options, type aliases,
inherited members and delegated/computed state are outside its finite scope.
Malformed Kotlin, missing files, wrong package, missing or duplicate canonical
owners exit 2 with a fixed error message that contains no raw input. All inputs
are validated before any findings are emitted. Findings have stable file/line
locations and exit 1; zero findings exit 0. There is no baseline or exemption.

The wrapper reuses `native_share.provider_boundary.tooling`: existing pinned
cached compiler jars and project JDK only, with no dependency or framework change.
Its compile cache binds the guard source, full jar hashes and JDK version. Input
files are parsed fresh on each run. `--root` selects the complete two-file scope;
`--cache-dir` permits private verification outputs.

The existing mandatory PR/release gate and required-gate assertion invoke both
independently runnable commands; the authored root census registers their entrypoints:

```
python3 tools/architecture/native_notification/retired_declaration.py
python3 tools/architecture/native_notification/prove_declarations.py
```

The fixture command executes the actual Python CLI and checks diagnostics and
locations across valid, invalid and input-error cases. The original two source
files must report exactly two findings; the repaired current source must report
zero. Runtime measurements use those same two-file inputs and are informational.
The existing eight `NotificationInteractionSecurityTest` methods retain their
purpose/replay/expiry/replacement/storage/target assertions. The existing isolated
`scripts/test_native_monitoring_count.py` checks exactly one foreground monitoring
record with ID `214601`. Those existing behavioral checks remain necessary;
passing this structural rule does not replace them.

Runtime and compilation measurements belong in ignored architecture-program evidence.
Measure cold compilation and repeated warm checks with the same two-file inputs,
compiler/JDK pins and fingerprint. Timing remains informational; it never changes
the correctness result.
