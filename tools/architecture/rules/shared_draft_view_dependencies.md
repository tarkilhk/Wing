# ARCH_SHARED_DRAFT_VIEW_DEPENDENCIES

The completed `lib/core/screens/shared_draft_review.dart` library and its actual
parts must not expose these canonical raw workflow namespaces:

- `lib/core/services/profile_workspace_controller.dart`
- `lib/core/services/attachment_draft_service.dart`
- `lib/core/services/android_share_intent_service.dart`
- `lib/core/models/composer_work.dart`

The original review imported all four and owned destination paging, recovery,
retry targets and composer staging. `SharedDraftSession` now owns the captured
workflow and publishes copied disclosure and issued destination observations.
The review borrows that session; Home owns its lifetime and navigation. The
existing controller/composer store, attachment service and native queue keep
execution, file and acknowledgment authority. `composer_work` is included
because it exposed the old raw saved-work/recovery records, rather than copied
review facts. Connection metadata and unrelated pure identity types are not
blanket prohibited.

This command configures the unchanged `checkViewAdapterDependencies` helper.
It follows direct imports/exports, local export closure, all conditional
alternatives, normalized relative/package paths and actual parts. Prefixes and
show/hide do not waive this declared boundary. An imported typed session may
import these dependencies internally: ordinary transitive imports are not
traversed. Unrelated homonymous libraries and members remain valid. Missing or
ambiguous selected library, roles, parts or visible authored namespace produce
`ARCH_INPUT` and exit 2. A boundary finding exits 1; clean input exits 0.

```sh
dart run tools/architecture/rules/shared_draft_view_dependencies.dart --json
dart run tools/architecture/tests/shared_draft_view_dependencies_test.dart
flutter test test/shared_draft_view_dependency_guard_test.dart
```

Seven small fixtures cover each of the four canonical dependencies, a real
part, a barrel, the typed session/model and unrelated homonyms, plus missing
part input. Three existing representative shapes run the actual source CLI
with exact identity/location and empty-valid-output checks, and an explicit
completeness assertion for exits 1/0/2. The accepted shared-helper fixtures own
its broader namespace cases; no new resolver or framework is added here.

This finite structural guard cannot detect arbitrary renamed policy or prove
immutable observations, current captured chat authority, native ACK ordering,
cancellation or transactional draft retention. Existing public controls in
`test/shared_draft_review_test.dart`, `test/home_share_review_test.dart` and
`test/profile_shared_draft_test.dart` remain necessary. The post-ACK navigation
fence specifically refuses a changed selected profile/chat while an already
admitted native acknowledgment is allowed to settle. No rollback of that ACK
or replay of staged content is inferred. Exact removed view identities can be
added to the existing retirement manifest separately. Root owns production
original/successor CLI proof, host validation and CI/root registration. This
source-only handoff reports no executed proof or timing acceptance.
