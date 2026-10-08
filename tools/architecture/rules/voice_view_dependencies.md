# ARCH_VOICE_VIEW_DEPENDENCIES

The completed `lib/core/screens/administration/admin_voice_page.dart` library
and actual parts cannot import/export the canonical administration repository or
profile gateway namespace. Originally `AdminVoicePage` captured raw profile
access, read config/schema and discovered default fields during rendering.
`ProfileVoiceController` now owns those typed observations; the view forwards
navigation intent through required callbacks.

This independent command reuses the unchanged view-adapter namespace checker:
direct imports/exports, local export closure, conditional alternatives, normalized
relative/package URIs and actual parts count. Prefixes or show/hide do not waive
a declared dependency. Ordinary imports of typed owners may import adapters
internally. Unrelated homonyms and separate `admin_voice_routes.dart` captured
composition remain valid; no blanket feature exemption exists.

Six focused cases cover original direct repository import, gateway barrel,
actual part, typed owner/model with separate composition, unrelated homonyms and
missing-part input. Only original invalid, typed valid and missing input also
invoke the CLI, proving exits 1/0/2. Accepted capabilities fixtures retain the
shared algorithm's wider evidence; no repeated matrix or resolver is added.

```sh
dart run tools/architecture/rules/voice_view_dependencies.dart --json
dart run tools/architecture/tests/voice_view_dependencies_test.dart
flutter test test/voice_view_dependency_guard_test.dart
```

Findings exit 1; valid input exits 0; missing/ambiguous scope or unsupported
visible namespaces exit 2. This guards declared dependencies, not arbitrary
symbol dataflow, schema policy, captured selection or asynchronous authority.
Existing voice owner/page controls establish those behavioral properties.
Renamed canonical paths require a contract update. Root owns production
original/successor proof, formatting, CI and focused execution; source authorship
does not claim SDK/runtime proof or timing measurements.
