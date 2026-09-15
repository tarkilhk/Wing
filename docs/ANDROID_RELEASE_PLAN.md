# Android release guide

This guide covers this fork's build identity and release checks. Source versions do not imply published artifacts. Check [the releases page](https://github.com/tarkilhk/wing/releases) for published APKs and [the changelog](../CHANGELOG.md) for release changes.

## Identity and versioning

| Build | Application ID | Signing |
| --- | --- | --- |
| Wing release | `com.tarkilhk.wing` | Existing Wing release key |
| Ordinary development | `com.tarkilhk.wing.dev` | Android debug key |
| Wing development | `com.tarkilhk.wing` | Existing Wing key, explicitly enabled by the development build script |

Wing uses a new application ID and starts with separate local app data. Never uninstall an existing app to bypass a signature mismatch. Updates that preserve data require the same application ID, a compatible signing certificate and an acceptable version code.

Read the source version and base build number from [pubspec.yaml](../pubspec.yaml). For split APKs, Gradle computes `base * 10 + ABI`, where ARMv7 is 1, ARM64 is 2 and x86_64 is 3. For example, base 2227 gives ARM64 code 22272. This is an example, not a second source of the current version.

`pubspec.yaml` is the version source. The release helper updates it and the changelog; workflows and tests do not need per-release edits. Stable tags use `v<major>.<minor>.<patch>`. Both the version and base build number must advance beyond earlier Wing tags. Published Wing tags and assets are never overwritten.

Wing begins at `1.0.0`. The displayed version starts a new series while the Android build number continues increasing. `scripts/release-history-start` pins the Wing package-identity commit; only tags descended from that commit participate in version comparisons. Keep that boundary fixed. The older Hermes tags describe a different application and do not constrain Wing's version. The inherited version tags were removed from this fork before the first Wing release, leaving `v1.0.0` available for Wing. Their source commits remain in Git history. The helper refuses all existing tag names.

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

The build script's default Windows signing directory is `%LOCALAPPDATA%/Wing/signing`. The script expects `wing.p12` and loads its DPAPI-protected credential, supplies signing through process environment variables and checks the certificate, package, version code and debuggable flag:

```powershell
./scripts/build-wing-release.ps1 -ToolchainRoot '<toolchain-root>' -OptimizeAndroid
```

`-OptimizeAndroid` enables the smaller optimized distribution APK. The toolchain root contains `flutter`, `jdk-17` and `android-sdk`. `-InitializeSigning` is for first provisioning only; it refuses an existing directory. Do not generate a replacement key for updates. `-Development` produces a debuggable Wing build and must not be distributed as a production release.

The public certificate fingerprint is pinned in `android/wing-release-certificate.sha256`. Keep a protected, portable backup of the keystore and password; the DPAPI credential file alone cannot be moved to another Windows account or machine.

CI signing uses three repository secrets: `KEYSTORE_BASE64`, `STORE_PASSWORD`, and `KEY_PASSWORD`. `KEY_ALIAS` is a repository Actions variable. Local Gradle signing also accepts repository-root `key.properties` or all four `WING_STORE_FILE`, `WING_STORE_PASSWORD`, `WING_KEY_ALIAS` and `WING_KEY_PASSWORD` environment variables. Keep the keystore and passwords out of source, release notes and logs.

Before installation, inspect the built artifact with Android build tools. Verify package, effective version code, non-debuggable status and the expected certificate. Test a signed release on a phone: connect, stream a reply, reopen history, switch profiles, interrupt and recover a send, attach/queue files, open an output and check notification routing.

## GitHub APK distribution

### Prepare a release

Use Python 3.10 or newer and Git from the checkout root (on Windows, use `py -3` instead of `python3`). Add user-facing changes under `## Unreleased` in `CHANGELOG.md`, then choose a bump:

```sh
python3 scripts/release.py prepare patch --dry-run
python3 scripts/release.py prepare patch
```

| Bump | Use for | Example from 1.0.0 |
| --- | --- | --- |
| `patch` | Bug fixes and small improvements | 1.0.1 |
| `minor` | New features | 1.1.0 |
| `major` | Breaking changes | 2.0.0 |

Every bump increments the Android base build number by one. The helper moves Unreleased notes into a dated release entry and leaves an empty Unreleased section for future work. It edits only `pubspec.yaml` and `CHANGELOG.md`; review and commit those changes through the normal PR/merge process. It refuses empty notes and repeated preparation without new notes. It does not build an APK locally.

### Trigger CI after merging

Once the preparation is merged, update your local `main`, then:

```sh
git switch main
git pull --ff-only origin main
python3 scripts/release.py publish --dry-run
python3 scripts/release.py publish
```

`publish` requires a clean tree, local `main` matching `origin/main`, dated changelog notes, and an unused version tag. It fetches remote tags, validates version/build progression, creates an annotated tag at the current commit and pushes only that tag to `origin`. The dry run fetches and validates without creating or pushing a tag. A failed tag push leaves the local tag in place and prints the retry command.

The tag starts [the Release workflow](../.github/workflows/release.yml):

1. Confirm the tag matches the source version and its commit is on `main`.
2. Run release-tool tests, Flutter analysis and Flutter tests.
3. Build signed ARMv7, ARM64 and x86_64 APKs with the pinned toolchain.
4. Verify every APK's package, architecture, effective version code, version name, non-debuggable status and expected signing certificate using Android build-tools `36.0.0`.
5. Package APKs, Dart symbols, changelog notes, source/certificate metadata and `SHA256SUMS`.
6. In a separate job with `contents: write`, create a draft release, upload all assets, download them again and verify checksums, then publish automatically.

The build job has read-only repository access; signing secrets are supplied only to the build step and the temporary keystore is removed afterward. Actions are pinned to commit revisions. Runs for the same ref are serialized. Keep tag creation restricted to trusted maintainers; Actions workflow and build-script changes should be reviewed before tagging. Enable immutable releases in GitHub repository settings if desired; the workflow itself refuses to overwrite an existing release. See [GitHub's action security guidance](https://docs.github.com/en/actions/reference/security/secure-use) and [draft release support](https://cli.github.com/manual/gh_release_create).

### Configure signing once

In GitHub **Settings → Secrets and variables → Actions**, add these three entries under **Secrets**:

| Secret | Value |
| --- | --- |
| `KEYSTORE_BASE64` | Base64 encoding of the intended Wing release keystore |
| `STORE_PASSWORD` | Keystore password |
| `KEY_PASSWORD` | Signing key password |

Under **Variables**, add `KEY_ALIAS` with the signing key alias. The workflow reads it through `vars.KEY_ALIAS`.

The certificate must match `android/wing-release-certificate.sha256`. Keep the private keystore and passwords out of commits and logs. Uploading secrets and pushing a real release tag are separate from preparing the source changes.

A manual Release workflow run uses the workflow and release tooling on `main` to build and publish an existing version tag. Set the required `release_tag` input to the tag being retried:

```sh
gh workflow run release.yml --ref main -f release_tag=v1.0.0
```

This allows a workflow fix to retry an unpublished release while preserving the tag's exact application source. The workflow checks out tooling and source separately; `release.json` records both the source commit and workflow commit. Run release scripts from the source checkout root. Manual runs on other branches are skipped. Signing requires all three secrets and the alias variable.

### Downloads and failures

Release assets include `wing-vX.Y.Z-arm64-v8a.apk` (most current phones), the ARMv7 and x86_64 alternatives, a symbols archive, `release.json`, `release-notes.md`, and `SHA256SUMS`. The same assets remain available as an Actions artifact for 30 days; the GitHub Release retains the symbols alongside the APKs.

If building or verification fails, fix the cause before retrying. If a failed publication leaves a draft, inspect it and delete only that unpublished draft before rerunning the publish job. An already published release is never replaced: prepare a new version. A tag's source commit must not be moved to fix code; use a new version tag. Verify a downloaded release on a phone using the acceptance checks above.

## Google Play preparation

The existing workflow does not upload to Play Console. A Play release needs an Android App Bundle:

```sh
flutter build appbundle --release
```

Configure and verify the intended upload/app-signing arrangement before distribution. An AAB normally uses the base version code rather than the split-APK override. Plan an upgrade code above existing distributed APK codes if those users must migrate under the same package and signing identity. Do not infer the AAB code from an ARM64 APK name.

Before submitting, verify the final bundle on a device and follow [Android's page-size checks](https://developer.android.com/guide/practices/page-sizes). Prepare the store description from [the maintained listing text](../fastlane/metadata/android/en-US/full_description.txt), screenshots from the actual release, and reviewer access to a disposable compatible server if required.

Publish [PRIVACY.md](../PRIVACY.md) at a public URL and enter that URL in Play Console. The app already bundles the same policy for offline reading in App settings. Complete Data safety using [the data-handling inventory](PLAY_DATA_SAFETY.md) and the actual artifact's SDK configuration. This document does not represent completed Play Console declarations. Include complete license/copyright notices consistent with the [recorded upstream MIT identification](../NOTICE.md).

## Local data and backups

Android isolates storage by package ID, so this identity starts with separate
local data. Wing exports and imports `wing-config` backups in a
`wing-config-encrypted` envelope. Backups from the previous identity are rejected;
connections and settings must be configured again. Recovery journals are not
migrated. Hermes retains server conversation data independently.
