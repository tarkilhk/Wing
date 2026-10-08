# ARCH_SPEECH_SYNTHESIS_VIEW_DEPENDENCIES

The completed `lib/core/screens/administration/admin_speech_synthesis_page.dart`
library and actual parts cannot expose these canonical adapter namespaces:
administration repository, profile gateway, profile voice repository,
`controllers/voice_output_controller.dart`, and `services/android_voice.dart`.
The original view constructed the configuration writer and native player and
owned raw provider/readiness/mutation policy. The existing typed
`ProfileVoiceController` now owns configuration, autosave admission, provider/setup
workflow and delegated sample playback. Views retain focus, dialogs and navigation.

This independent command reuses the unchanged view-adapter namespace checker.
Direct imports/exports, local export closure, conditionals, normalized URIs and
actual parts count; prefix/show-hide does not waive the dependency. Ordinary
transitive imports of the typed owner are allowed. Separate
`admin_voice_routes.dart` captures real profile/device/settings/credential
composition and is outside this completed library, without a feature exemption.

Six focused cases cover original direct repository import, a barrel exposing
gateway/voice repository/player/device adapters, actual part, typed owner/model
internally importing those adapters, unrelated homonyms and missing-part input.
Three CLI representatives prove exits 1/0/2. Existing capabilities fixtures
retain shared namespace robustness; no resolver or variants matrix is added.

```sh
dart run tools/architecture/rules/speech_synthesis_view_dependencies.dart --json
dart run tools/architecture/tests/speech_synthesis_view_dependencies_test.dart
flutter test test/speech_synthesis_view_dependency_guard_test.dart
```

Findings exit 1; valid input exits 0; missing/ambiguous scope or unsupported
visible namespaces exit 2. This protects declared dependency ownership, not all
renamed policy or symbol dataflow. Exact admitted autosave durability, ACK versus
readback, current-route physical dispatch, saved-profile-only speech and native
retirement need existing owner/page behavioral controls. Renamed canonical paths
require a contract update. Root owns production original/successor proof,
formatting, CI and focused execution; this source handoff claims no executed
proof or runtime measurement.
