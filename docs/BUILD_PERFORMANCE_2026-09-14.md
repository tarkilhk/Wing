# Android build performance, 2026-09-14

The [controlled follow-up](BUILD_PERFORMANCE_2026-09-14_FOLLOWUP.md) records
45-46 second signed release edits, resource cleanup, and the Flutter launcher guard.

The repeated wait comes from different work depending on what changed. A Dart
edit reruns the Dart frontend and AOT compiler. An Android version-code change
reruns resource processing, Android Lint, and R8 even when Dart is unchanged.
Starting in a fresh snapshot adds native compilation and cache setup again.

The personal build script now disables Android code/resource shrinking by
default. It still produces a signed, non-debuggable ARM64 release APK with Dart
AOT compilation, icon tree shaking, and Android Lint. `-OptimizeAndroid` restores
full Android optimization. Standard CI Flutter builds retain full optimization.

## Measurements

Profiling used the copied 2.31.21 source, Flutter 3.44.0 / Dart 3.12.0, AGP 9.0.1,
Gradle 9.1.0, Kotlin 2.3.20, and Java 17. The laptop has eight logical processors
and about 32 GiB of RAM. The checkout used for the profiles is
`C:\Users\rober\Documents\Projects\hermes-android`.

Gradle ran with `--profile --quiet --console=plain`, the same ARM64/release/signing
inputs as Flutter, and Flutter's six SDK-version Dart defines. Compiler target
timings were collected with `-Pperformance-measurement-file`. The instrumentation
path was kept constant after its first run to avoid invalidating inputs between
scenarios. No clean command was used between the measured updates.

Times below cover the Gradle invocation, not dependency resolution, APK signature
verification, installation, or publication. Task durations can overlap; do not
add them to reconstruct wall time.

| Scenario | Elapsed | Main task costs |
| --- | ---: | --- |
| No source or version change | 29.47 s | Dart, R8, and Lint up to date; Gradle startup 11.76 s and project configuration 2.93 s |
| One Dart UI-title change | 160.67 s | Flutter task 131.99 s; R8 0.04 s and Lint 0.08 s, both up to date |
| Only Android version code incremented | 120.31 s | R8 87.86 s; Lint 25.56 s; resource processing 7.97 s; Dart up to date |
| First build with Android shrinking disabled | 159.04 s | One-time D8 artifact transforms and external dex merge, 80.30 s for the merge |
| Next version-code increment without shrinking | 25.88 s | Resource processing 8.08 s; Lint 7.59 s; D8 and Dart up to date; no R8 task |
| App-only task, no changes | 17.60 s | `:app:assembleRelease` |
| Root task control, no changes | 19.37 s | `assembleRelease`; only 1.77 s slower in this comparison |

The Dart compiler's own measurements split the UI edit into 56.48 s in
`kernel_snapshot_program`, 62.59 s in `android_aot`, and 10.89 s in asset-bundle
work. R8 was not the cause of that Dart-only wait. Conversely, the version-code
experiment left Dart up to date and made R8 run again.

Other Android tasks ran on this laptop during parts of the investigation. Two
active AOT compiler processes were observed during the Dart-edit experiment.
These numbers identify the work performed and removed, but are not a promise of
the same speedup under every machine load. No OneDrive-only A/B comparison was
completed.

The initial profiled run used verbose Gradle logging and changed the profiling
input. It took 152.98 s, so it is excluded from the steady-state comparisons.
Its report remains available to inspect input invalidations. An earlier direct
Gradle probe omitted Flutter's SDK-version defines and was stopped; it is also
excluded. Later runs used matching defines and normal quiet logging.

## CPU and historical evidence

A Java Flight Recorder capture of the initial build in the new checkout lasted
66 seconds. Of 684 execution samples, 627, or 91.7%, contained R8/D8 frames.
This is the CPU sample share during that interval, not the share of the entire
build. A separate thread dump during the first uncached local build showed
Android Lint's Kotlin/UAST analysis running. The task profiles above distinguish
those phases quantitatively.

The historical `technical-release-2.31.19-build.log` records 1109.8 s in Gradle.
A repeat in that existing snapshot took 172.1 s in Gradle and 194.83 s including
the release script's other work. A fresh local workspace still took 807.3 s in
Gradle and 823.23 s overall. The subsequent first build in the chosen Git checkout
took 295.8 s in Gradle and 315.16 s overall. Those builds differ in cache state,
source, and machine load, so they do not isolate a filesystem effect.

Gradle logged free physical memory below 1 GiB and stopped a daemon to reclaim
memory around the historical slow build. Two emulators used roughly 5.2 GiB
combined during the investigation. This supports avoiding overlapping builds;
it does not prove that heap tuning alone fixes the compiler work above.

## Changes and tradeoffs

- Build directly in the persistent checkout outside OneDrive. Preserve `build/`,
  `.dart_tool/`, and `android/.gradle/` instead of creating a directory for each
  release version. The original checkout is retained because existing tasks
  were still using it during relocation.
- Enable `org.gradle.caching=true`. Nine task rows were restored from cache in
  the first no-shrink profile. The Dart compile task is not Gradle-cacheable in
  this Flutter version, so keeping Flutter's own local state still matters.
  [Gradle build cache documentation](https://docs.gradle.org/current/userguide/build_cache.html).
- Default the personal script to `--android-project-arg=shrink=false`, which the
  installed Flutter Gradle plugin supports. This removes the repeated R8 pass.
  Android documents optimization as an additional build cost, appropriate for
  the final version tested for publication.
  [Android optimization guidance](https://developer.android.com/topic/performance/app-optimization/enable-app-optimization).
- Add a named mutex to reject overlapping personal-script invocations across
  checkouts, and print build duration and workspace. Direct Flutter/Gradle
  commands and older script copies do not participate in this lock.
- Restore the original heap/worker defaults. The early 4 GiB heap / two-worker
  experiment was not independently established as a speed improvement. The
  task comparisons above used those same experimental limits on both sides;
  final script validation uses the retained defaults.

The measured full-optimization APK was 22,480,111 bytes. The no-shrink probe was
27,522,407 bytes: about 5.04 MB larger, or 22.4%. The latter retains more Android
code/resources and omits R8's native Java/Kotlin optimizations. Dart release AOT
remains enabled. This is a deliberate build-time/size tradeoff, not an identical
binary or a measured claim about phone startup performance.

The first no-shrink build pays for new D8 outputs. Subsequent updates reuse them.
Frequent switching between full and fast modes can invalidate outputs again.
No Android Lint, Dart analysis, or test gate was disabled. Configuration-cache
work was not pursued because measured warm project configuration was only a few
seconds. App-only task selection saved under two seconds in its control run, so
no task-selection workaround was added.

## Commands

```powershell
Set-Location 'C:\Users\rober\Documents\Projects\hermes-android'
# Normal personal phone update
.\scripts\build-personal-release.ps1 -ToolchainRoot 'C:\Users\rober\Development\android-dev'
# Smaller APK with full Android optimization
.\scripts\build-personal-release.ps1 -ToolchainRoot 'C:\Users\rober\Development\android-dev' -OptimizeAndroid
```

Source edits still need Dart frontend/AOT compilation to produce a release APK.
For changes that need immediate visual feedback, Flutter's debug hot reload
avoids rebuilding a release APK for each edit.
[Flutter hot reload](https://docs.flutter.dev/tools/hot-reload).

## Evidence and cleanup

Gradle HTML profiles are under `build/reports/profile/` in the new checkout.
The main reports are:

- `profile-2026-09-14-02-34-37.html`: no change.
- `profile-2026-09-14-02-38-27.html`: Dart-only change.
- `profile-2026-09-14-02-41-11.html`: version-code-only change with R8.
- `profile-2026-09-14-02-48-59.html`: version-code-only change without R8.

Logs and compiler timing JSON files are retained under `build/performance/`.
JFR recordings and parsed execution samples are retained in `build/`.
Temporary UI-title and local version changes were restored after each scenario.
No diagnostic APK was installed or published.

Cleanup removed five obsolete `build/app/intermediates` directories from the
old 2.31.12, 2.31.13, 2.31.16, 2.31.17, and 2.31.18 snapshots, freeing 1.31 GiB.
Source snapshots, archived APKs, mappings, and symbols were retained. There was
about 286 GiB of free disk space, so this was housekeeping rather than evidence
of a disk-capacity bottleneck.

## Relocation and final validation

The selected checkout is a standalone Git clone with the existing GitHub origin.
It was synchronized through commit `f8dc746`, version `2.31.23+2208`. A stash
preserves the earlier copied working tree at
`74bab64ff9be473456c50c906c0f60316f62abac`. Reapplying that snapshot exposed stale
release-number and partial UI conflicts. Comparing the conflict hunks with the
completed commits showed those changes were already incorporated. The newer
completed code was retained, along with the build-performance changes. The
original checkout and its index were not reset or deleted.

The relocated checkout passed 23 tests across release identity, composer
controls, activity detail layout, and combined activity. PowerShell parsing and
the named-mutex rejection path also passed. The mutex then prevented the final
validation build from overlapping the other task's optimized 2.31.23 build.

The script and configuration changes were initially kept reviewable in both
checkouts. Existing tasks still point at the original folder. Use the selected
local folder for future work; no task was automatically relocated or interrupted.
The final normal personal script built version `2.31.23+2208` in the new clone
in **173.15 seconds end to end**, with **161.3 seconds in Gradle** and 170.3
seconds including Flutter dependency resolution. This run recompiled the newer
Dart source and used the restored 8 GiB Gradle heap defaults. It is not the
version-only scenario in the comparison table. Signature verification matched
the existing personal certificate; AAPT confirmed package
`com.tarkilhk.hermes.android`, version `2.31.23`, ARM64 version code `22082`, and
no debuggable flag. The APK is 27,522,407 bytes. Logs and timing metadata are
`build/performance/final-script.log` and `final-script-result.json`.
An unchanged script repeat immediately after that build took 105.06 seconds,
including 93.5 seconds in Gradle. This is longer than the earlier direct Gradle
no-change profile and must not be presented as a 26-second script build. A
subsequent verbose diagnostic trace explicitly skipped both
`kernel_snapshot_program` and `android_aot_release_android-arm64`. It reran the
asset bundle because Flutter uses a missing wildcard sentinel to detect newly
added assets. Enabling verbose logging also changed the Gradle `verbose` input
and Android Lint's `printStackTrace` input, which reran Lint. That diagnostic run
took 68.4 seconds including Flutter dependency resolution and is excluded from
normal-mode timing claims. Evidence is `build/performance/script-cache-trace.log`.
After restoring quiet logging, the first script run took 49.81 seconds. The
next consecutive unchanged run took **33.15 seconds end to end**, with **22.5
seconds in Gradle** and 30.9 seconds including Flutter dependency resolution.
Both passed the same signature and APK identity checks. The steady-state
result demonstrates cache reuse through the actual user command, while the
105.06-second transitional repeat above remains recorded rather than hidden.
Its exact frontend invalidation trigger was not captured by that quiet run.
The trace confirms compiler reuse on the subsequent run, but does not establish
the reason for every earlier invalidation. Logs and metadata are
`final-quiet-restored*` and `final-quiet-repeat*` under `build/performance/`.

The temporary hermes-android-release-build workspace was removed after stopping
the verified idle profiling daemon that held its Lint JAR files open. The unused
marker-only workspace under LocalAppData was also removed. The selected Git
clone, its active caches, and all profiling evidence were retained.

## Further investigation and shared build configuration

A real Dart edit in the ordinary development APK took 60.96 seconds; restoring
that edit and rebuilding took 60.97 seconds. The compiler timing split was
10.60 seconds in the frontend and 5.05 seconds in debug asset preparation, with
no AOT compiler step. The initial development build took 271.30 seconds to
prepare native outputs. These measurements used the same small app-title edit
as the earlier release probe, but were taken later and are not a controlled
same-load speedup ratio against the contended release run.

The personal script now accepts `-Development`. This selects Dart JIT and uses
an explicitly gated Gradle property to preserve the Personal package, signing
key, and ABI version-code scheme. The default development app identity remains
separate unless that property is supplied. The signed Personal development APK
was verified as `com.tarkilhk.hermes.android`, version `2.32.0-dev`, code `22092`,
with the accepted personal certificate and the debuggable flag. Its initial
build after configuration/source updates took 102.74 seconds. No APK from this
investigation was installed on the phone.

Development mode trades runtime optimization and APK size for faster build
cycles. The development APK before the compression experiment was 95,803,942
bytes. The attach helper targets the Personal app on an explicitly selected
connected device, enabling the normal Flutter hot-reload workflow. Phone
hot-reload timing has not yet been measured.
[Flutter build modes](https://docs.flutter.dev/testing/build-modes) and
[hot reload](https://docs.flutter.dev/tools/hot-reload).

The next Gradle profile identified 23.67 seconds in Flutter's debug task and
7.77 seconds in `compressDebugAssets`. Skipping compression of the 78.65 MB
kernel snapshot increased the APK to 148.51 MB. A guarded dependency receipt
was also tested to skip pub only when dependencies, SDK and plugin registries
matched a verified build. Its invalidation checks passed, but the combined
source-edit run still took 65.46 seconds. Neither change established a useful,
repeatable improvement in the actual script, so both were removed. They are
not part of the shipped build configuration.

A further repeat took 185.45 seconds. Gradle daemon logs show why it cannot be
used as a clean comparison: at 03:57:29 a build in the separate temporary
`hermes-queued-message-device-qa` checkout occupied the warm daemon. This build
started a fresh daemon at 03:58:03 while that work was still running. Other
checkouts continued to contend for shared Gradle caches during later checks.
This confirms a limitation of the original PowerShell-only mutex.

The shared settings now acquire an OS file lock through a Gradle build service.
All tasks retain the service for the build, and Gradle releases it on completion.
Direct Gradle and Flutter builds using these settings reject a competing Hermes
build, rather than starting overlapping compilation. A real cross-process lock
probe verified rejection while another process held the file and successful
configuration after release. Old snapshots without these settings remain outside
the guard and must update from main.
[Gradle build services](https://docs.gradle.org/current/userguide/build_services.html).

Configuration-cache support was tested and rejected. Flutter's `DebugMinSdkCheck`
attempted to serialize unsupported project/configuration objects; the diagnostic
build failed with six reported problems. Configuration caching stays disabled.

The release workflow now uses `gradle/actions/setup-gradle@v4` to retain Gradle
dependencies and local build-cache entries. Its default policy writes caches on
main; tagged builds can reuse main's cache. A manual release-workflow run on main
can seed it without publishing a tagged release. CI speedup is not yet measured.
[Gradle setup action](https://github.com/gradle/actions/blob/v4/docs/setup-gradle.md).

Further evidence is retained in `build/performance/debug-*`,
`personal-development-*`, `personal-debug-*`, `development-final-*`, and
`gradle-build-lock-*`. The real source and version metadata were restored after
all temporary edits. The latest three release-identity tests passed, and the
missing-signing configuration guard correctly rejected an unsigned Personal
development build.

The retained shared configuration also completed a normal signed release build
of commit fa7436d in 269.67 seconds, including 254.9 seconds in Gradle. Its
certificate, package, version code and non-debuggable flag passed verification.
This was a source/configuration transition, not an unchanged-build timing, and
was not used to claim a release-speed improvement. The sub-30-second source-edit
APK target remains unmet. Phone hot-reload validation requires approval to
replace the installed release app with the verified development APK.

## Final committed-build validation

Commit d4a77c0 passed the complete PR quality workflow after correcting two
checks. The Android identity contract now sees an explicit ordinary Dev resource
default before the guarded Personal override. The administration navigation test
scrolls to Diagnostics, which moved below the viewport in the preceding feature
commit. The nine affected tests passed locally; no check was disabled.

The committed Personal development build took 109.93 seconds after the source
and configuration transition. An unchanged repeat took 75.44 seconds. The same
small title edit took 99.43 seconds with a 25-second Gradle JFR recording during
part of that run; restoring the source and rebuilding without that recording
took 76.73 seconds. All APK identity and signature checks passed. These later
results prevent treating the earlier 61-second measurements as a reliable bound.
The real source was restored, and no APK was installed on the phone.

The short trace caught Gradle waiting for its Flutter child process, followed
by file traversal and ZIP compression. It does not establish another dominant,
safely removable Gradle phase. The source-edit APK target is still unmet.
Evidence is in build/performance/committed-*.

CI logs also showed roughly 54-62 seconds repeatedly spent setting up the same
Flutter SDK. Both workflows now enable the action's SDK cache, with its pub
cache disabled because the existing dedicated dependency cache owns that work.
The first run must populate the SDK cache; a speedup is not yet measured.
[Flutter action cache inputs](https://github.com/subosito/flutter-action/blob/v2/action.yaml).