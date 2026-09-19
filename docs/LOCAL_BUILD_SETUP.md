# Windows build workflow

Start with [Contributing](../CONTRIBUTING.md) for the pinned toolchain and basic checks. Use a persistent checkout outside a synchronized folder for Android builds. Keep `build/`, `.dart_tool/` and `android/.gradle/` between updates so incremental builds can reuse their outputs. Do not create a fresh version-named checkout for each release.

The examples assume a toolchain directory containing `flutter`, `jdk-17` and `android-sdk`. Substitute your own path and run from the checkout root.

## Guarded Flutter commands

```powershell
./scripts/invoke-flutter.ps1 -ToolchainRoot '<toolchain-root>' -FlutterArguments @('pub', 'get')
./scripts/invoke-flutter.ps1 -ToolchainRoot '<toolchain-root>' -FlutterArguments @('analyze', '--no-pub', '--fatal-infos')
./scripts/invoke-flutter.ps1 -ToolchainRoot '<toolchain-root>' -FlutterArguments @('test', '--no-pub')
```

The launcher checks write access to Flutter's SDK cache before starting its Windows batch file. It reports denied access immediately and waits at most 30 seconds for a busy bootstrap lock. It does not delete locks or alter permissions. An installed SDK still needs a writable cache.

Run tests and builds sequentially because they share generated plugin registration. The Wing build script uses a cross-checkout mutex, and the shared Gradle settings use an OS file lock. Older source snapshots without these guards are not covered. Investigate the owning process before retrying a lock failure.

Keep Gradle's build cache enabled. Configuration cache was not usable with the pinned Flutter 3.44 integration during the build audit; do not enable it merely to remove a warning. Avoid speculative heap changes, cache deletion or antivirus exclusions as routine build steps.

## Wing release and development builds

```powershell
./scripts/build-wing-release.ps1 -ToolchainRoot '<toolchain-root>'
./scripts/build-wing-release.ps1 -ToolchainRoot '<toolchain-root>' -OptimizeAndroid
./scripts/build-wing-release.ps1 -ToolchainRoot '<toolchain-root>' -Development
```

The default is a signed, non-debuggable ARM64 release. It skips Android code/resource shrinking while retaining Dart AOT, icon tree shaking and Android Lint. `-OptimizeAndroid` enables shrinking for distribution. Ordinary CI release commands remain optimized.

`-Development` uses the Wing package and signing key with debugging enabled. It is labelled Wing Dev, is larger, and is unsuitable for judging release startup, animation or battery use. A matching signature and sufficient version code allow an in-place update that preserves app data. Ordinary Flutter debug builds use the separate `.dev` package.

See [Release guide](ANDROID_RELEASE_PLAN.md) for signing setup and artifact verification. Do not replace a signing key or uninstall an existing app to bypass an update failure.

## Performance builds

Use an AOT profile build when judging scrolling or loading performance:

```sh
flutter build apk --profile --build-number=<next-version-code>
```

This builds the separate `com.tarkilhk.wing.dev` package, labelled Wing Dev and
signed with the ordinary debug key. It can update an ordinary debug installation
in place with `adb install -r`, preserving that app's saved connections. It does
not update the signed `-Development` installation that uses the release package.
Profile mode supports performance inspection but not hot reload. Keep debug and
profile timing results separate. For repeatable Chats measurements use
`tools/performance/chat_frames.dart`; ordinary builds omit its frame observer.

## Hot reload

After installing and opening Wing Dev, attach from its source checkout:

```powershell
./scripts/attach-wing-development.ps1 -ToolchainRoot '<toolchain-root>' -DeviceId '<device-id>'
```

Find the ID with `flutter devices`. Press `r` for hot reload, `R` for Dart restart or `d` to detach. The helper attaches without installing an APK. Native changes require a build; hot-reloaded changes also need a new APK to survive a cold relaunch.

## Device testing

Use a disposable emulator for integration tests. With the pinned Flutter runner, use `--no-uninstall` to avoid cleanup deleting the app's local data. On a phone, verify the artifact first and use explicit `adb install -r`; stop if the upgrade fails. Do not allow an uninstall fallback to erase drafts and connections.

See [Testing](TESTING.md) for live-backend prerequisites and the distinction between fixture, emulator and phone evidence.
