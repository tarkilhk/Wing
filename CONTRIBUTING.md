# Contributing

Start with [Getting started](docs/GETTING_STARTED.md) for the user flow and [Explore Wing](docs/FEATURES.md) for a product overview. The [documentation index](docs/README.md) points to detailed references. Check the current app and stock Hermes API before claiming a capability exists.

## Development setup

Use Flutter 3.44.0 and bundled Dart 3.12, Java 17, Android SDK platform/build-tools 36 and the checked-in Gradle wrapper. Match CI and retain `pubspec.lock`. Install Android command-line tools and accept the SDK licenses for your own environment. Check `flutter doctor` before building.

From the actual checkout root:

```sh
flutter pub get
dart run tools/architecture/check_all.dart
dart run tools/architecture/rules/activity_density.dart
dart run tools/architecture/rules/required_quality_gates.dart
dart run tools/architecture/rules/dart_main_roots.dart
dart run tools/architecture/rules/completed_setup_view.dart
dart run tools/architecture/rules/app_preferences_view.dart
python3 tools/architecture/rules/authored_census.py
python3 -m unittest discover -s tools/qa -p 'test_*.py' -v
flutter analyze --fatal-infos
python3 scripts/test.py
flutter build apk --debug
```

`python3 scripts/test.py` runs product tests and all current-source linters.
Use `python3 scripts/test.py --full` for the complete checker fixture, CLI,
native compilation and SDK proofs as well. CI runs the complete suite nightly,
when checking tools or their inputs change, and before a published release. The test
inventory and coverage boundary are documented in [Testing](docs/TESTING.md).

The ordinary debug APK uses `com.tarkilhk.wing.dev`, keeping its app storage separate from Wing. No release key is needed for development. Release signing is covered in [the release guide](docs/ANDROID_RELEASE_PLAN.md).

On Windows with the repository's toolchain layout, use the guarded launcher:

```powershell
./scripts/invoke-flutter.ps1 -ToolchainRoot '<toolchain-root>' -FlutterArguments @('pub', 'get')
./scripts/invoke-flutter.ps1 -ToolchainRoot '<toolchain-root>' -FlutterArguments @('analyze', '--no-pub', '--fatal-infos')
./scripts/invoke-flutter.ps1 -ToolchainRoot '<toolchain-root>' -FlutterArguments @('test', '--no-pub')
./scripts/invoke-flutter.ps1 -ToolchainRoot '<toolchain-root>' -FlutterArguments @('build', 'apk', '--debug')
```

That root contains `flutter`, `jdk-17` and `android-sdk`. The launcher reports SDK-cache access failures promptly instead of entering Flutter's bootstrap retry loop. The [Windows build workflow](docs/LOCAL_BUILD_SETUP.md) covers incremental builds, Wing development builds and hot reload.

Run tests and Android builds sequentially. Do not remove another process's locks. Reuse build caches for ordinary iteration, and use a separate workspace for independent work. Existing local changes belong to their author; keep them intact.

## Local commit checks

Enable the tracked hook once per clone:

```sh
python3 scripts/install_git_hooks.py
```

If your machine needs a shell file to activate Flutter, Java and the Android
compiler cache, pass its absolute path with `--toolchain-env`. That path is stored
only in local Git configuration. The installer preserves an existing hook setup
by requiring its reconciliation before replacement.

Every commit on every branch then runs the existing Dart and Python/native source
linters against an isolated checkout of the Git index. Unstaged edits cannot hide
a staged violation or contaminate a clean staged commit. Dart rules share one VM
startup; native checks reuse their source/JDK/compiler-bound caches.
Unchanged source trees also share parsing within that batch; current files and
roles are reread and every rule computes fresh findings. Missing
tooling blocks the commit with a setup error. Initialize dependencies with
`flutter pub get` and the ordinary Android build above before the first check.
The hook runs source checks; behavior tests and builds remain in CI.

For a manual check of the working tree, run:

```sh
python3 scripts/check_commit_linters.py
```

Git hooks are local configuration and can be bypassed by Git. The quality
workflow also runs on pushes to every branch and on PRs targeting `main`; its
required-gate linter rejects narrowing the branch trigger or adding path filters.

## Source paths

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | App wiring, connections and notification navigation |
| `lib/core/screens/profile_workspace_screen.dart` | Conversation UI and composer |
| `lib/core/screens/profile_workspace_browser.dart` | Profiles, projects, chats and Activity |
| `lib/core/services/profile_workspace_controller.dart` | Canonical workspace commands, transport and lifetime admission |
| `lib/core/services/profile_gateway.dart` | Scoped HTTP and RPC operations |
| `lib/core/services/attachment_draft_service.dart` | Attachment preparation and upload |
| `android/app/src/main/kotlin/` | Android sharing, clipboard and native viewers |

Use [the architecture map](docs/ARCHITECTURE.md) for current feature ownership:
`ComposerSession` owns unsent work and ordered persistence, `TranscriptReading`
owns history and paging, and `ChatRuntime` owns execution, recovery and pending
input. Browser and supervision sessions borrow canonical observations; workspace
mutations use captured commands. Test-only saved message inspection lives under
`integration_test/support/`; it does not define the production renderer. Check
`lib/main.dart` and supported integration or performance entry points before
adding another implementation of an existing flow.

## Changes and checks

For feature work, behavior fixes, refactoring and deletion, follow the
[feature-maintenance skill](tools/agent_skills/maintain-feature-architecture/SKILL.md).
Update affected ownership, contracts and manifests alongside the code. Historical
cleanup snapshots remain in `plans/`; current ownership lives in the architecture
map and live role/root manifests.

Read [AGENTS.md](AGENTS.md) before UI changes. Use [the design system](docs/DESIGN_SYSTEM.md) and its shared light/dark tokens. Administration changes also require [the ownership handoff](docs/design/2026-09-14-administration-handoff.md).

Keep connection/profile/chat ownership intact. Preserve newer composer text during asynchronous operations. Hermes remains authoritative for saved conversation state. Do not introduce backend patches or infer server support from a fixture. Prefer a regression test at the failing behavior's real boundary for reliability changes.

The [architecture contracts](tools/architecture/README.md) define independently
runnable guards and their fixtures. The architecture migration baseline is empty.
PR checks compare it with the preceding baseline and reject new exceptions or
stale entries. Both quality and release workflows require the architecture and
offline QA gates as hard failures.

Choose local checks and retries using
[verification scope and stopping](docs/TESTING.md#verification-scope-and-stopping).
Published releases retain the full-suite gate in the release checklist; local
builds and phone installs use the applicable existing evidence.
Tests under `integration_test/` and opt-in live tests may create chats, change profile settings or use providers. Read each test's environment flags and cleanup behavior before running it against an explicitly authorized server. Ordinary `flutter test` does not replace device or live-server acceptance.

A useful change description explains the user-visible result, its boundaries, tests run and remaining limits. Update the relevant guide when behavior changes. Put revision-specific test results in the PR or issue, and keep generated logs/captures out of current instructions. Check new Markdown links from their file's directory.

## Reporting problems and provenance

Use [Wing's issues](https://github.com/tarkilhk/Wing/issues) for reproducible client bugs. Include Android/client versions, backend revision if known, expected behavior and minimal steps. Follow [SECURITY.md](SECURITY.md) before attaching logs or screenshots.

Preserve existing MIT attribution and applicable third-party license notices. See [NOTICE.md](NOTICE.md). Record the license of any new third-party component.
