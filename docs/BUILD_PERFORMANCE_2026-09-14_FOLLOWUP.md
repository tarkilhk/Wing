# Release build profiling follow-up, 2026-09-14

The normal signed release command now measured 46.01 seconds after a small Dart
edit and 44.58 seconds when restoring that edit. An unchanged build took 15.47
seconds. These include dependency resolution and APK signature/identity checks.
They used commit c5eab37, a persistent local checkout, retained caches, the
existing personal signing key, ARM64, Dart release AOT, and disabled Android
shrinking. No development APK was installed. Full Android shrinking remains
available through `-OptimizeAndroid` and was not part of these timings.

These are controlled small-edit results, not an upper bound for every change.
They were taken during an agreed pause in other Flutter commands/source edits,
with the leftover QA emulator temporarily paused. The emulator was resumed
and the other task released after profiling. The temporary source edit was
restored byte-for-byte, and HEAD remained c5eab37 throughout the controlled runs.

## Resource contention and cleanup

Before this round's builds, Windows reported 100% total CPU. A sample attributed
about four cores to the emulator. Numerous old Flutter cmd shells were also
busy despite having no child compilers. Twenty-three shells older than an hour
had consumed 35.9 CPU-hours in total. Those stalled shells were stopped under
the user's cleanup approval. A remaining stalled test shell and its abandoned
PowerShell parent were subsequently stopped after verification.

Stopping the old shells removed their CPU load. It did not immediately idle
the machine: a separate release build had started, the emulator still used
over three cores, and other desktop processes were active. Source changes also
landed during the initial baseline, so that run is excluded from controlled
comparisons. Its 108.76 seconds and the next 48.24-second unchanged repeat remain
recorded rather than being used as an isolated speedup ratio.

The emulator's sampled CPU use fell from over three cores to 0.02 cores after
pausing it. This is direct evidence of recoverable CPU capacity. The resulting
build improvement cannot be assigned entirely to the new launcher, OneDrive,
or one Gradle setting; cache state, source stability and competing work matter.

The Windows Flutter bootstrap has an immediate `GOTO acquire_lock` retry for
its `flutter.bat.lock` file. The old shells' behavior is consistent with that
loop; their exact failure reasons were not captured before cleanup. A separate
real sandbox check now rejects an SDK-cache write in 0.23 seconds through the
new guard. The same guard successfully launches Flutter with the required
filesystem permission. The deterministic tests also cover a held lock and a
read-only lock file.

`scripts/invoke-flutter.ps1` checks SDK-cache write access and waits with a
200 ms sleep for at most 30 seconds if the bootstrap lock is busy. It never
deletes a lock or alters permissions. Both existing local build/attach scripts
use it, and the setup guide uses it for standalone analyze/test commands. It
preserves arguments and the Flutter exit code. This is a preflight check;
Flutter still owns its lock, and another process can acquire it between the
check and launch. Raw Flutter invocations remain outside the guard.

## Cache invalidation and compiler work

Stable diagnostic arguments were used across four direct Gradle runs:

| Scenario | Gradle wall time |
| --- | ---: |
| Instrumentation prime | 17.22 s |
| Identical repeat | 10.71 s |
| Small Dart title edit | 53.42 s |
| Original source restored | 48.29 s |

The unchanged repeat kept `compileFlutterBuildRelease` up to date. The edit's
invalidation log named the changed `lib/main.dart`; the AOT invalidation named
the resulting `app.dill`. There was no unexplained frontend/AOT rebuild in this
controlled sequence. The Dart frontend took 21.85 seconds and AOT 17.79 seconds
for the edit; restoration took 19.45 and 16.71 seconds respectively.

Some asset copying and CMake checks intentionally reran. Flutter's asset
wildcard sentinel also triggers asset-bundle work after compilation. These
checks did not cause a minutes-long repeat. The unchanged Gradle report measured
1.217 seconds configuring projects, 0.310 seconds in settings/buildSrc, and
1.540 seconds of startup. No correctness check was disabled to save this time.

After returning to the normal script and quiet logging, the end-to-end results
were 15.47, 46.01 and 44.58 seconds as reported above. Each APK passed the existing
personal certificate, package and non-debuggable checks. Keeping a stable
release workspace and avoiding competing builds/QA is the operating requirement
for reproducing these results.

## Defender, disk activity and CPU limits

The user approved a Windows UAC prompt for a 240-second Defender performance
recording. Antivirus settings were unchanged. Java was associated with 2,316
scans totaling 19.73 seconds of cumulative scan duration. Individual Java scans
maxed out at about 102 ms. The leading Java-accessed files included Gradle
transform and registry lock files; no single generated app file dominated.

Cumulative scan durations can overlap and do not equal removable wall time on
the build's critical path. This trace establishes scanning overhead but does
not justify treating Defender as the cause of the earlier multi-minute waits.
The trace overlaps the active release work and cleanup period; it is not an
antivirus-on/off experiment. No exclusion was added.

Sampled Windows CPU performance-limit flags were zero and the reported
performance limit was 100%. This supplies no positive evidence of a reported
CPU performance cap in those samples. It does not rule out all thermal or
power effects. The Balanced power scheme was left unchanged.

## Flutter configuration-cache failure

The release-specific command `gradlew :app:ReleaseMinSdkCheck
--configuration-cache` failed in four seconds with six problems, five unique.
Flutter's task captures an Android Variant and Gradle Project in its execution
closure. Gradle consequently tries to serialize unsupported configuration,
dependency-handler, project and Kotlin-service objects; traversal also reaches
a Java ReferenceQueue. This is separate from Gradle's enabled task-output cache.

The matching upstream issue is open and triaged. It also identifies a second
capture in Flutter's APK assembly action, so disabling the minimum-SDK check is
not a complete fix. The proper fix is to give task actions serializable values
or declared providers instead of live configuration objects. No compatible fix
was verified for the pinned Flutter 3.44.0 SDK, and no SDK fork or reflection
workaround was introduced. With warm project configuration measured at 1.217
seconds, this is not the remaining minute-scale bottleneck.
[Flutter issue #192035](https://github.com/flutter/flutter/issues/192035).

## Validation and evidence

The launcher tests passed for argument/exit-code forwarding, preservation of
existing lock contents, bounded busy-lock waiting and denied-write handling.
All changed PowerShell files parsed successfully. The normal signed release
script passed three times with the guard integrated.

Local evidence is retained under `build/performance/release-round2/`,
`build/performance/round2-trace-*` and the 08:09-08:10 Gradle HTML reports. The
Defender ETL and detailed process data remain local ignored artifacts. They
are not part of the Git commit.