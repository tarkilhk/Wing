# Native share provider boundary

An external provider previously ran on the same serialized executor as share
acknowledgment and camera reservations. A held `getType`, metadata query, open or
read therefore held every later local operation. The new owner separates foreign
work from the durable intake actor; provider interruption is best effort only.

## Resource and lifetime contract

- The local actor has one worker and 32 queued operations. Admission rejects
  overload explicitly; rejected channel commands settle on the main thread.
- Four provider leases cover two workers and two waiting operations. Each has an
  absolute 15-second admission deadline, including queue wait. Expired queued
  attempts cannot invoke a provider. Timed-out workers are never replaced.
- Cleanup has two workers and four queued tasks. At most four resource-bearing
  leases exist. A lease retains its admission permit until its producer actually
  exits, every owned close actually returns, publication finishes or retires,
  and private-stage deletion succeeds. Two finishing cleanup runnables can still
  occupy workers after releasing permits, but retain no resources; queue four
  accommodates all newly admitted leases. A blocked close never releases a permit.
- Each batch has at most ten URIs and 64 MiB. Private staging has an explicit
  256 MiB aggregate byte cap across admitted leases. No per-attempt directory or
  file is allocated before work starts. The durable queue retains its existing
  128 MiB cap and camera reservation accounting.
- A timed-out producer may still return from kernel/provider I/O. Late opened
  resources transfer to the existing cleanup owner; checked writes and publication
  cannot proceed. Live staging is not deleted while its producer can still return.
  Failed stage deletion retains its permit and byte charge. Process-start cleanup
  removes only staging left by a previous process.
- Activity/engine authority fences callbacks and publication. The local actor
  rechecks the current durable queue and camera reservation before renaming a
  complete private stage and persisting its record. Detachment retires old foreign
  attempts; committed intake remains durable. Text-only shares need no provider
  permit.

These are bounded-resource and ownership guarantees. They do not promise to stop
an uncooperative provider or bound kernel I/O duration. Saturated provider capacity
rejects additional foreign imports while local acknowledgment/camera work remains
independent.
The lease counts Wing's client calls and acquired resources. Android can return
from asynchronous `ContentResolver.getType` after its own MIME-query timeout while
the remote Binder provider continues; Wing cannot count or stop that remote server
execution. A null MIME observation may legitimately use the supplied intent MIME
and complete file import within Wing's deadline.

## Independent structural rules

```sh
python3 tools/architecture/native_share/provider_boundary.py --rule provider-boundary
python3 tools/architecture/native_share/provider_boundary.py --rule bounded-queues
python3 tools/architecture/native_share/provider_boundary.py --rule qa-isolation
python3 tools/architecture/native_share/provider_boundary.py
python3 tools/architecture/native_share/prove_boundary.py
```

`NATIVE_SHARE_PROVIDER_BOUNDARY` uses Kotlin PSI to restrict resolver acquisition
to the declared copy boundary and its callers to `providerWork.submit(work = ...)`.
It accepts nested iteration, getter spelling and unrelated queries; comments and
strings cannot manufacture findings. It rejects callable escape and acquisition
of a resolver alias on the local actor.

`NATIVE_SHARE_BOUNDED_QUEUE` separately checks explicit bounded executor/queue
constructors, bounded private-helper arguments and the declared local actor owner.
It handles imported aliases, rejects unbounded factory/static imports and prevents
CallerRuns from moving rejected provider work onto the submitting thread.

`NATIVE_SHARE_QA_ISOLATION` independently checks the controlled camera target.
Every `setClassName` use in MainActivity must be a direct fixed-fixture call in
an `if` branch requiring DEBUG, NATIVE_SHARE_QA and the exact Notification QA
application ID. It rejects callable escape, else branches, weaker conditions and
hoisted fixture-component strings, including escaped literal strings. Unrelated
classes and comments are accepted. Its Gradle PSI checks require explicit
true-only opt-in properties, unconditional native-QA implication of Notification
QA, a false default, the sole debug opt-in override and the isolated debug suffix.
BuildConfig declarations use direct calls and literal field names so this narrow
rule can inspect all overrides. Computed declarations require adapting this
contract rather than bypassing it. The independent fixture command is:

```sh
python3 tools/architecture/native_share/prove_qa_isolation.py
```

The mandatory `prove_boundary.py` also executes these actual 1/0/2 CLI fixtures;
the existing mandatory aggregate includes the new rule. This is a syntax contract
over the declared native/build ownership seam, not whole-program Kotlin dataflow
or a proof of packaged release flags. Android compilation and inspection of both
normal and opted-in APK configurations remain separate acceptance gates.

All rules are deliberately scoped syntax contracts over the native owner files
and QA build configuration,
not whole-program Kotlin symbol resolution or proofs of deadlines/close behavior.
Changing those owner interfaces requires adapting their rules. The fixture runner
executes each selected rule through its real CLI and verifies diagnostics, locations
and exits 1/0/2. Android compilation validates semantic symbol identity.

The runner uses the Android project's cached Kotlin 2.4.20 compiler and existing
JDK; it performs no installation or network access. Run it **after** Android
dependency setup in CI. Its ignored compile cache binds guard source, full compiler
dependency hashes and JDK version. Correctness failures are blocking; timing is
informational in CI. CI must also invoke the fixture proof without masking errors.

## Behavioral and native acceptance

```sh
python3 tools/architecture/native_share/run_owner_jvm.py
```

The Android-independent JVM regressions control held workers, held closes, queue
expiry, capacity rejection, late resource handoff, retired publication, byte caps
and local-actor overload. A generous watchdog detects a hung test; tight elapsed
assertions do not decide those ownership results. JVM executor tests do not prove
Android MethodChannel wiring or foreign-provider behavior.

The emulator matrix uses only synthetic content and the isolated Notification QA
package. Build with the project's Notification QA Gradle option, not the ordinary
app identity, and launch this opt-in entry point:

```sh
ORG_GRADLE_PROJECT_notificationQa=true ORG_GRADLE_PROJECT_nativeShareQa=true \
  flutter build apk --debug --no-pub --target-platform android-x64 \
  -t integration_test/share_intake_device.dart \
  --dart-define=WING_NATIVE_SHARE_QA=true
adb -s <emulator-id> install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s <emulator-id> shell am start -n com.tarkilhk.wing.notificationqa/com.tarkilhk.wing.MainActivity
python3 tools/qa/check_external_share.py --serial <emulator-id> --provider-faults \
  --output build/native-share-acceptance
```

The checker rejects physical devices and nonempty synthetic intake. It tests the
existing grant/private-file boundary before holding each foreign metadata/open/read
boundary for 45 seconds. Actual pending/ack/camera channel requests start together
and must settle within their generous three-second watchdog. The disposable
helper is an explicit capture target only in the opted-in isolated debug QA
build (`notificationQa=true`, `nativeShareQa=true`). Android 11 and later restrict
implicit capture to preinstalled cameras; the synthetic installed fixture cannot
become an implicit handler. Normal builds retain implicit camera routing. The
checker verifies the explicit helper target and leaves stock camera package
states untouched. An explicit nonce-scoped receiver cancels the held helper camera through
RESULT_CANCELED, so no input gesture or SystemUI readiness assumption is involved.
The actual MainActivity launch, FileProvider OUTPUT grant and ActivityResult are
used. A tiny JPEG success checks exact target, bytes/digest, durable committed
record after host process restart and one acknowledgment. The helper also
recreates while holding its output grant. A separate held query kills only the
background QA host, returns camera cancellation into its recreated process and
rejects old provider publication; fresh foreign admission clears abandoned stages.
The driver verifies the host PID and process name before killing it from its own
app UID, preserving ActivityResult recreation rather than force-stop semantics.
A no-op manifest broadcast wakes a cached/frozen helper while waiting for its
45-second producer to return; it never cancels the held I/O. This prevents the
Android cached-app freezer from substituting permanent suspension for the
required late-return check. Stock camera package states remain unchanged.
This proves process-death/recreation behavior, not every within-process activity
configuration or real hardware camera/gesture behavior; those phone gates remain
pending. Owned failure snapshots include helper command/outcome counters.
Query/open/read attempts still held past Wing's 15-second deadline cannot publish
a record, including after the provider returns, and staging must clean. Type lookup
may complete early under Android's own timeout: caller/timestamp evidence must show
the requests were submitted during that client wait, its correctly imported record
is acknowledged exactly once, and the late MIME callback cannot publish a duplicate.
Android pipe-read behavior is exercised; arbitrary blocked `close` is
covered by the controlled JVM resource, not claimed as an Android fixture result.
The checker removes its helper, synthetic files and port forward, and restores
native preferences. The loopback bridge is bounded, opt-in and absent from normal
production entry points; it makes no Hermes calls.

Run the same native fault driver against an isolated pre-change snapshot to prove
the original actor stalls before relying on its green result. Native compilation,
native tests, release isolation, queue/camera persistence and old-host recreation
remain required acceptance gates; a passing PSI rule does not substitute for them.

## Local feedback budget

The initial quiet-host measurements cover the actual three owner files, existing
project JDK and cached Kotlin compiler: one cold compilation/startup and the median
of three warm runs for each independent rule and their aggregate. Raw measurements,
host/JDK details and input hashes stay outside public Git per `docs/PERFORMANCE.md`.
The justified local budget is **10 seconds** for cold guard compilation plus
checking, and **1.5 seconds** for each warm rule or warm aggregate. Compare later
acceptance on the same host/configuration; optimize a demonstrated regression
rather than raising the budget. CI timing stays informational.

```sh
python3 tools/architecture/native_share/benchmark_guard.py \
  --output /tmp/wing-native-share-guard-budget.json
```

Stop other host builders during those measurements. Cache setup is measured
separately from warm feedback, and benchmark timings never change diagnostics.
