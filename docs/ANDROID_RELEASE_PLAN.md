# Android release guide

This guide covers this fork's build identity and release checks. Source versions do not imply published artifacts. Check [the releases page](https://github.com/tarkilhk/wing/releases) for published APKs and [the changelog](../CHANGELOG.md) for release changes.

## Identity and versioning

| Build | Application ID | Signing |
| --- | --- | --- |
| Personal release | `com.tarkilhk.hermes.android` | Existing Personal release key |
| Ordinary development | `com.hermesagent.hermes_android.dev` | Android debug key |
| Personal development | `com.tarkilhk.hermes.android` | Existing Personal key, explicitly enabled by the development build script |

The upstream package `com.hermesagent.hermes_android` is separate. Never uninstall an existing app to bypass a signature mismatch. Updates that preserve data require the same application ID, a compatible signing certificate and an acceptable version code.

Read the source version and base build number from [pubspec.yaml](../pubspec.yaml). For split APKs, Gradle computes `base * 10 + ABI`, where ARMv7 is 1, ARM64 is 2 and x86_64 is 3. For example, base 2227 gives ARM64 code 22272. This is an example, not a second source of the current version.

When bumping a release, update pubspec, both workflows' `REQUIRED_BASE_VERSION_CODE`, the release identity test and changelog together. Use a new tag matching `v<versionName>`. Do not overwrite a published tag or artifact.

## Validate one release candidate

Use a fixed revision and preserve the lockfile. Run Flutter commands sequentially; tests and builds share generated plugin registration. The repository also prevents overlapping Android builds across checkouts.

```sh
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter pub outdated
flutter build apk --release --split-per-abi
```

Record dependency update decisions rather than upgrading everything during a release. Follow [Contributing](../CONTRIBUTING.md) for toolchain requirements and the Windows launcher. Complete [CODE_QUALITY_CHECKLIST.md](../CODE_QUALITY_CHECKLIST.md). Live gateway tests are opt-in and require their own authorized disposable data.

## Sign and verify

Signing material stays outside Git. Ordinary release builds never fall back to the debug key; without release signing configuration, they are unsigned validation artifacts.

The maintainer's Windows signing directory is `%LOCALAPPDATA%/HermesPersonal/signing`. The existing script loads its DPAPI-protected credential, supplies signing through process environment variables and checks the certificate, package, version code and debuggable flag:

```powershell
./scripts/build-personal-release.ps1 -ToolchainRoot '<toolchain-root>' -OptimizeAndroid
```

`-OptimizeAndroid` enables the smaller optimized distribution APK. The toolchain root contains `flutter`, `jdk-17` and `android-sdk`. `-InitializeSigning` is for first provisioning only; it refuses an existing directory. Do not generate a replacement key for updates. `-Development` produces a debuggable Personal build and must not be distributed as a production release.

The public certificate fingerprint is pinned in `android/personal-release-certificate.sha256`. Keep a protected, portable backup of the keystore and password; the DPAPI credential file alone cannot be moved to another Windows account or machine.

CI signing uses `KEYSTORE_BASE64`, `STORE_PASSWORD`, `KEY_PASSWORD` and `KEY_ALIAS` in the repository secret store. Local Gradle signing also accepts repository-root `key.properties` or all four `HERMES_STORE_FILE`, `HERMES_STORE_PASSWORD`, `HERMES_KEY_ALIAS` and `HERMES_KEY_PASSWORD` environment variables. Never place values in source, release notes or logs.

Before installation, inspect the built artifact with Android build tools. Verify package, effective version code, non-debuggable status and the expected certificate. Test a signed release on a phone: connect, stream a reply, reopen history, switch profiles, interrupt and recover a send, attach/queue files, open an output and check notification routing.

## GitHub APK distribution

The existing release workflow tests, builds and verifies signed ABI-split APKs. A matching `v*` tag publishes them to this fork's GitHub Releases when the signing secrets are configured. An unsigned tagged release is rejected. A manual run without signing secrets produces explicitly labelled debug validation artifacts.

Publishing a release or uploading signing secrets is a separate action from editing source or this guide. Check the workflow and repository visibility before creating a release tag. Retain the release's source revision, verification results and symbol files.

## Google Play preparation

The existing workflow does not upload to Play Console. A Play release needs an Android App Bundle:

```sh
flutter build appbundle --release
```

Configure and verify the intended upload/app-signing arrangement before distribution. An AAB normally uses the base version code rather than the split-APK override. Plan an upgrade code above existing distributed APK codes if those users must migrate under the same package and signing identity. Do not infer the AAB code from an ARM64 APK name.

Before submitting, verify the final bundle on a device and follow [Android's page-size checks](https://developer.android.com/guide/practices/page-sizes). Prepare the store description from [the maintained listing text](../fastlane/metadata/android/en-US/full_description.txt), screenshots from the actual release, and reviewer access to a disposable compatible server if required.

Publish [PRIVACY.md](../PRIVACY.md) at a public URL and enter that URL in Play Console. The app already bundles the same policy for offline reading in App settings. Complete Data safety using [the data-handling inventory](PLAY_DATA_SAFETY.md) and the actual artifact's SDK configuration. This document does not represent completed Play Console declarations. Include complete license/copyright notices consistent with the [recorded upstream MIT identification](../NOTICE.md).

## Moving settings between packages

Android isolates storage by package ID. The encrypted configuration export/import can transfer connections, credentials and allowlisted preferences. It does not transfer every appearance setting, profile selection, draft, queue or recovery journal. Keep the old app until the new one works, and review unsent work before uninstalling. Hermes retains server conversation data independently.
