# Contributing

Start with [Getting started](docs/GETTING_STARTED.md) for the user flow and [the feature guide](docs/FEATURES.md) for delivered behavior. The [product plan](docs/PRODUCT_PLAN.md) owns scope. Dated plans and generated design boards do not establish that a backend operation exists.

## Development setup

Use Flutter 3.44.0 and bundled Dart 3.12, Java 17, Android SDK platform/build-tools 36 and the checked-in Gradle wrapper. Match CI and retain `pubspec.lock`. Install Android command-line tools and accept the SDK licenses for your own environment. Check `flutter doctor` before building.

From the actual checkout root:

```sh
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
```

The ordinary debug APK uses `com.hermesagent.hermes_android.dev`, keeping its app storage separate from Wing. No release key is needed for development. Release signing is covered in [the release guide](docs/ANDROID_RELEASE_PLAN.md).

On Windows with the repository's toolchain layout, use the guarded launcher:

```powershell
./scripts/invoke-flutter.ps1 -ToolchainRoot '<toolchain-root>' -FlutterArguments @('pub', 'get')
./scripts/invoke-flutter.ps1 -ToolchainRoot '<toolchain-root>' -FlutterArguments @('analyze', '--no-pub', '--fatal-infos')
./scripts/invoke-flutter.ps1 -ToolchainRoot '<toolchain-root>' -FlutterArguments @('test', '--no-pub')
./scripts/invoke-flutter.ps1 -ToolchainRoot '<toolchain-root>' -FlutterArguments @('build', 'apk', '--debug')
```

That root contains `flutter`, `jdk-17` and `android-sdk`. The launcher reports SDK-cache access failures promptly instead of entering Flutter's bootstrap retry loop. The [Windows build workflow](docs/LOCAL_BUILD_SETUP.md) covers incremental builds, Personal development builds and hot reload.

Run tests and Android builds sequentially. Do not remove another process's locks. Reuse build caches for ordinary iteration, and use a separate workspace for independent work. Existing local changes belong to their author; keep them intact.

## Source paths

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | App wiring, connections and notification navigation |
| `lib/core/screens/profile_workspace_screen.dart` | Conversation UI and composer |
| `lib/core/screens/profile_workspace_browser.dart` | Profiles, projects, chats and Activity |
| `lib/core/services/profile_workspace_controller.dart` | Ownership, commands, drafts and recovery |
| `lib/core/services/profile_gateway.dart` | Scoped HTTP and RPC operations |
| `lib/core/services/attachment_draft_service.dart` | Attachment preparation and upload |
| `android/app/src/main/kotlin/` | Android sharing, clipboard and native viewers |

## Changes and checks

Read [AGENTS.md](AGENTS.md) before UI changes. Use [the design system](docs/DESIGN_SYSTEM.md) and its shared light/dark tokens. Administration changes also require [the ownership handoff](docs/design/2026-09-14-administration-handoff.md).

Keep connection/profile/chat ownership intact. Preserve newer composer text during asynchronous operations. Hermes remains authoritative for saved conversation state. Do not introduce backend patches or infer server support from a fixture. Prefer a regression test at the failing behavior's real boundary for reliability changes.

Run analysis and relevant tests, then the full suite before a release. Tests under `integration_test/` and opt-in live tests may create chats, change profile settings or use providers. Read each test's environment flags and cleanup behavior before running it against an explicitly authorized server. Ordinary `flutter test` does not replace device or live-server acceptance.

A useful change description explains the user-visible result, its boundaries, tests run and remaining limits. Update the relevant guide when behavior changes. Put revision-specific test results in the PR or issue, and keep generated logs/captures out of current instructions. Check new Markdown links from their file's directory.

## Reporting problems and provenance

Use [this fork's issues](https://github.com/tarkilhk/wing/issues) for reproducible client bugs. Include Android/client versions, backend revision if known, expected behavior and minimal steps. Follow [SECURITY.md](SECURITY.md) before attaching logs or screenshots.

Preserve existing MIT attribution and applicable third-party license notices. See [NOTICE.md](NOTICE.md). Record the license of any new third-party component.
