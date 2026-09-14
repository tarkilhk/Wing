# Local Android build setup

These are maintainer-specific machine and performance notes. Contributors should
start with [Contributing](../CONTRIBUTING.md); no particular Windows username or
checkout location is required. Dated paths below preserve their original context.

The owner selected `C:\Users\rober\Documents\Projects\hermes-android` on
2026-09-14. Build directly from this persistent checkout outside OneDrive with
the existing `C:\Users\rober\Development\android-dev` toolchain. Keep `build/`,
`.dart_tool/`, and `android/.gradle/` between updates. Creating a fresh release
snapshot for each version discards useful incremental state.

```powershell
Set-Location 'C:\Users\rober\Documents\Projects\hermes-android'
.\scripts\build-personal-release.ps1 -ToolchainRoot 'C:\Users\rober\Development\android-dev'
```

The personal script uses signed, non-debuggable ARM64 release builds. It skips
Android R8/code and resource shrinking for faster updates, while retaining Dart
AOT release compilation, icon tree shaking, and Android Lint. Add
`-OptimizeAndroid` when producing the smaller fully optimized Android APK.
The standard Flutter commands in CI retain full optimization.

Use the guarded launcher for standalone Windows Flutter commands too:

```powershell
.\scripts\invoke-flutter.ps1 -ToolchainRoot 'C:\Users\rober\Development\android-dev' -FlutterArguments @('analyze', '--no-pub')
.\scripts\invoke-flutter.ps1 -ToolchainRoot 'C:\Users\rober\Development\android-dev' -FlutterArguments @('test', '--no-pub')
```

The launcher checks write access to Flutter's SDK cache before starting the
Windows batch file. Flutter's bootstrap retries a denied/busy lock without a
sleep, which can leave a shell consuming CPU indefinitely. The guard reports
access denied immediately and waits at most 30 seconds for a busy bootstrap
lock. It neither deletes locks nor changes SDK permissions. Commands still need
permission to write the SDK cache even when the SDK is already installed.
The release and development-attach scripts use this guard automatically.

Run tests before the release build, and keep one Android build active at a time.
The personal script rejects overlapping invocations across checkouts with a
named mutex. The shared Gradle settings also reject overlapping builds across
checkouts with an OS file lock. This covers direct Flutter and Gradle commands
that use the updated settings. Older snapshots must update first. Keep one workspace for each genuinely simultaneous development
stream and reuse it rather than creating a version-named directory every time.

The profiling results and tradeoffs are recorded in
[the build performance report](BUILD_PERFORMANCE_2026-09-14.md). The original
OneDrive checkout is retained to protect work in existing tasks. New work should
use the selected local checkout.

The 2026-09-12 verification used the OneDrive checkout and an ignored
`build/camera-release` snapshot. The disposable Android 36 QA device was
`Hermes_Roadmap_QA`, `emulator-5556`. The relocation and verification below are
historical. See [the emulator record](EMULATOR_ROADMAP_VERIFICATION.md) for
device results.

## Faster personal development APKs

For everyday functional changes, add `-Development` to the personal build script.
This uses Dart's development compiler instead of release AOT compilation. It
builds an ARM64 APK signed by the existing Personal key, with the same package
name and ABI version-code scheme. The launcher label becomes Hermes Personal
Dev. An Android update with the matching key and a sufficient version code keeps
the app's stored data. This task verifies the artifact; it does not install it.

```powershell
.\scripts\build-personal-release.ps1 -ToolchainRoot 'C:\Users\rober\Development\android-dev' -Development
```

Development mode enables assertions and debugging, produces a larger APK, and
can run more slowly than release. Use release mode to judge animation, startup,
battery, and runtime performance. The first development build prepares a separate
set of native outputs; keep those caches for later source edits.

For the shortest feedback loop, run the development app through Flutter on the
phone and use hot reload for Dart edits. Reload updates running Dart code without
rebuilding an APK. Native Android changes still need a build. See
[Flutter hot reload](https://docs.flutter.dev/tools/hot-reload).

After installing the development APK, connect the phone using USB or wireless
ADB, open Hermes Personal Dev, and attach from this same checkout:

```powershell
.\scripts\attach-personal-development.ps1 -ToolchainRoot 'C:\Users\rober\Development\android-dev' -DeviceId '<phone-id>'
```

Use `flutter devices` to find the phone ID. In the attached terminal, press `r`
after a Dart edit. Press `R` when a change needs a Dart restart, and `d` to detach.
This helper attaches to the existing app; it does not install or replace an APK.
Hot reload updates the running process, so build a fresh APK when the changes
need to survive closing and relaunching the app.
## Historical Windows checkout, 2026-09-06

On 2026-09-06, development moved to
`C:\Users\rober\Development\hermes-android` on Prestige. The OneDrive checkout
was kept intact. Git history and all 311 tracked or untracked nonignored files
matched before work resumed in the new folder. Generated build caches were
excluded and dependencies were restored with `flutter pub get`.

Tools remain outside the checkout in
`C:\Users\rober\Development\android-dev`. Use these commands in PowerShell:

```powershell
Set-Location 'C:\Users\rober\Development\hermes-android'
$env:JAVA_HOME = 'C:\Users\rober\Development\android-dev\jdk-17'
$env:ANDROID_SDK_ROOT = 'C:\Users\rober\Development\android-dev\android-sdk'
$flutter = 'C:\Users\rober\Development\android-dev\flutter\bin\flutter.bat'
& $flutter pub get
& $flutter analyze
& $flutter test
& $flutter build apk --debug
```

Relocation verification: static analysis reports no issues; 974 tests pass and
one environment-dependent live gateway test is skipped. A fresh debug APK builds
successfully at `build/app/outputs/flutter-apk/app-debug.apk`. The running API 36 AVD
is `Hermes_API_36`, visible to ADB as `emulator-5554`.

The profile-aware milestone still needs full emulator end-to-end verification,
including background completion across profile switches and notification routing.
Use the unmodified installed Hermes gateway. The owner explicitly prohibits
Hermes backend modifications. Do not prepare or deploy backend patches, add
legacy compatibility, or make server changes a prerequisite for this client.

## Historical Linux setup

Prepared on 2026-09-06 for this workspace. The checkout is
`/home/dev/projects/hermes-android/hermes-android`; downloaded tools and caches
live outside the Git checkout in `/home/dev/projects/hermes-android/.toolchain`.

## Activate and verify

```bash
source /home/dev/projects/hermes-android/.toolchain/env.sh
cd /home/dev/projects/hermes-android/hermes-android
flutter pub get
flutter analyze --no-pub --fatal-infos
flutter test --no-pub
flutter build apk --debug --no-pub
```

The environment script sets the Flutter/Java/Android paths and keeps Pub and
Gradle caches in the local toolchain directory. Source it in each new shell.

## Installed tools

- Flutter 3.44.0 and bundled Dart 3.12.0, matching the repository's CI pin.
- Eclipse Temurin JDK 17.0.20.1+1.
- Android command-line tools, platform-tools, SDK platform 36, build-tools 36.0.0.
- Android NDK 28.2.13676358, selected and installed by the build.
- SDK platforms 34 and 35 and CMake 3.22.1, required by dependencies and installed
  automatically during the first build.
- Gradle 9.1.0 through the repository wrapper.

Flutter, Java, and Android command-line archives were checked against published
SHA-256 checksums before extraction. Android SDK licenses are accepted.
Dependencies were resolved with the existing lockfile; no package upgrade was
requested.

## Baseline verification

- Static analysis: no issues with `--fatal-infos`.
- Flutter tests: 947 passed.
- Debug APK: successfully built at `build/app/outputs/flutter-apk/app-debug.apk`.
- `flutter doctor` recognizes the Android toolchain and accepted licenses.
- No Android emulator or physical device was connected for runtime verification.

## Emulator preparation

**Superseded by the owner's Windows decision:** use `WINDOWS_HANDOFF.md` to
continue on the Windows laptop. The owner explicitly declined further VM
hardware-acceleration troubleshooting. The following is historical setup status.

The Android emulator and API 36 Google APIs x86_64 image are installed. A Pixel 7
AVD named `hermes_api36` is configured under `.toolchain/avd`, and the environment
script sets `ANDROID_AVD_HOME` to that directory. AVD creation emitted a missing
system-image `devices.xml` warning, but created the Pixel 7 configuration and
`emulator -list-avds` lists it; a boot has not yet been verified.

On the VM host, `/dev/kvm` exists but the `dev` account lacks access.
`emulator -accel-check` reports that permission failure. Automatic approval review
rejected persistently adding `dev` to the `kvm` group without explicit approval
for that privilege change. No group or device-permission change was made, and
the emulator has not been booted.

The fork owner also offered the Windows Hermes Desktop-managed local gateway as
the test backend. The preferred backend can therefore be the existing Windows
installation; no separate Hermes server has been deployed on this VM. Running
the emulator and development task on Windows is an alternative to completing
VM acceleration setup. Verify the installed gateway's endpoint, authentication,
and required profile REST/RPC contracts before connecting Android.

Build/test/doctor logs are under `/home/dev/projects/hermes-android/.toolchain`.
Web and Linux-desktop toolchain warnings from `flutter doctor` are outside this
Android setup.

The build reports an existing warning about plugins applying the Kotlin Gradle
Plugin and a future Flutter requirement to migrate to built-in Kotlin. It does
not block the pinned Flutter 3.44.0 build. Dependency upgrades were not part of
this baseline setup.

The debug build uses `com.hermesagent.hermes_android.dev`. Distribution signing
is separate: a production release needs a private release keystore and the
repository's signing configuration. No production signing key was installed.
