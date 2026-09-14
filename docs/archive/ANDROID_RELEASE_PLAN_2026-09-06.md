> Historical release notes retained on 15 September 2026. Use [the current release guide](../ANDROID_RELEASE_PLAN.md) for new builds. Relative links and machine paths below describe the original record.

# Android release plan

Deployed on 2026-09-11: the app-shell update is `2.1.2+2145`, ARM64 code `21452`, with the existing Personal certificate verified. Wireless ADB installation succeeded on the owner's Samsung phone and preserved existing data. See [app-shell delivery notes](../APP_SHELL.md). The installed-version observations below are the historical 2026-09-06 baseline.

Updated on 2026-09-06. The owner confirmed that the older app belongs to someone
else, so this fork uses a separate identity and signing key. No public release
or GitHub signing-secret upload has been performed.

## Current state

- Dev package: `com.hermesagent.hermes_android.dev`.
- Personal release package: `com.tarkilhk.hermes.android`, labelled Hermes Personal.
- The older upstream package remains `com.hermesagent.hermes_android`.
- The owner's phone has all three packages. The older release reports version
  `2.1.0`, effective version code `21402`; Personal is `2.1.1`, code `21412`.
- A new personal signing key is stored outside Git under
  `%LOCALAPPDATA%\HermesPersonal\signing`. The directory is restricted to the
  current Windows user and SYSTEM. `password.dpapi.xml` holds a Windows-encrypted
  credential, not a plaintext password. GitHub has no signing secrets configured.
- Release builds deliberately do not fall back to a debug signing key.
- The public certificate fingerprint is pinned in
  `android/personal-release-certificate.sha256`. Both the local release script
  and CI reject an APK signed with a different key. The fingerprint is public
  verification material, not the private signing key.

## Application identity

To update the installed release app in place, recover its original signing key
and verify that the certificate matches the installed APK before attempting an
update. Do not generate a replacement key with the same package ID and then
uninstall the existing app to bypass a signature mismatch.

The separate personal identity coexists with both existing apps. The Dev package
ID is deliberately unchanged so subsequent debug builds keep its saved data.
Static launcher shortcuts target the matching package explicitly, preventing a
shortcut from launching the other installed Hermes app. Internal native class
and Flutter channel names do not need to change with the distribution identity.

## Repeat the Windows build

From the repository root on Prestige:

```powershell
./scripts/build-personal-release.ps1 -ToolchainRoot C:/Users/rober/Development/android-dev
```

The script loads the protected credential, supplies signing through process
environment variables, builds a release arm64 APK and verifies its signature,
application identity and non-debuggable status. It clears signing variables
afterward. `-InitializeSigning` is for initial provisioning only and refuses to
overwrite an existing signing directory. Do not generate a replacement key for
future updates.

Run tests before the release script, not concurrently in the same checkout.
Flutter commands share generated Android plugin registration; a test run can
reintroduce the test-only plugin while a release build excludes its dependency.
The script also deliberately omits `--no-pub`: Flutter 3.44 skips the mode-specific
plugin-registry regeneration with that flag, leaving test-only registration in
place after a previous debug/test run. Dependencies still follow pubspec.lock.

Keep `hermes-personal.p12` and its password in a secure, portable backup. DPAPI
binds the encrypted credential to this Windows account/computer; copying only
`password.dpapi.xml` to another machine is insufficient. A password-manager or
encrypted offline backup still needs to be arranged with the owner. Never print
the signing password in agent logs or chat to facilitate a backup.

Android verifies update identity through application ID and signing certificate.
Keep a protected backup of the signing key and its passwords for future updates.
[Android signing guidance](https://developer.android.com/studio/publish/app-signing).

## First private release

1. Use the protected Windows build script above. CI may instead configure the
   chosen keystore through repository-root `key.properties`, which this repo
   ignores. This location differs from Flutter's default example.
2. Choose an unused version/tag and increase the version code. The current
   `2.1.1+2141` produces arm64 split code `21412`. Both quality and release
   workflows currently pin the base code to `2141`; update those assertions
   together with future version bumps. Never overwrite an existing release tag.
3. Run analysis and tests, then build the normal entry point:
   `flutter build apk --release --target-platform android-arm64 --split-per-abi -t lib/main.dart`.
4. Verify the APK signature with `apksigner`, package ID, effective version code,
   and that the packaged application is not debuggable. Retain symbol files if
   building with split debug information.
5. Install with `adb install -r` only after checking identity/signature. Confirm
   launch, gateway login, profile isolation, history, notifications, background
   recovery and the principal chat actions in release mode.

A signed APK is sufficient for direct installation; Play Store publication is
not required. A Play release uses an Android App Bundle and a separate publishing
workflow. [Flutter Android deployment](https://docs.flutter.dev/deployment/android).

## Dev-to-release settings

Different package IDs have separate Android app storage. Keep Dev installed
until the release is working. The existing encrypted configuration export/import
can transfer saved connections and credentials; do not write them to a plaintext
transfer file or commit a backup. The current backup allowlist does not include
the new accent preference, profile selections, drafts or pending-turn journals.
It is not a complete app-state migration. Stored conversations remain on Hermes
and are fetched after reconnecting to the correct host/profile. Review unsent
drafts before any later uninstall.

## Repeatable distribution

After the owner chooses a distribution channel, configure the existing release
workflow with `KEYSTORE_BASE64`, `STORE_PASSWORD`, `KEY_PASSWORD` and `KEY_ALIAS`
using GitHub's secret store. Never paste their values into committed files or
logs. Inspect repository visibility before uploading APKs. A unique version tag
triggers the existing workflow to test, sign and publish APKs to GitHub Releases.
This is direct-download distribution, not automatic in-app updates. Play internal
testing is an alternative when managed updates become worth the setup.

Creating a public release, uploading signing secrets and uninstalling existing
apps are not authorized by this plan itself.
