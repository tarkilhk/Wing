# Find and organize chats and projects

Filter and open the intended chat, manage its project or row actions, and return to the retained browser after a change or failed read.

Feature ID: `chat-browser`.

## Sub-features

- `chat-browser.find` — Search and filter chats and projects.
- `chat-browser.open` — Enter the captured row immediately.
- `chat-browser.organize` — Change a chat or project and retain browser state. The current-project card in Move to project has an icon-only cross to remove a chat from its project. Confirmation moves it to the captured profile's default folder, keeping messages and drafts. New projects start in the captured profile's default folder and propose a kebab-case subfolder as the name changes; typing or choosing a location keeps that override.

## How to get to it (user POV)

Choose Chats in the drawer. Search or filter by profile and project, tap a row to open it, use row actions to organize it, or long-press New chat to reveal New project.

To remove a chat from its project, open Move to project from its row actions or
tap the project in the conversation header. Tap the cross in Current project,
then confirm. Cancel keeps the assignment. Chats already in the default bucket
have no removal cross. A failed move keeps the picker open with an error and retry.
If the chat is still working, confirmation shows why it cannot move. Retry in
the same picker after the work finishes; admission uses the current chat state.
Choosing another project and tapping the removal cross use the same Move chat
confirmation, naming the destination and keeping messages and drafts.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/chat_browser_transport_test.dart test/profile_workspace_browser_test.dart test/profile_row_actions_test.dart
  flutter test --no-pub test/project_picker_design_test.dart
  flutter test --no-pub test/server_files_repository_test.dart test/profile_project_management_test.dart test/profile_project_actions_test.dart test/project_folder_picker_test.dart test/project_icon_picker_test.dart
  ```

- **Android `journeys`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py journeys --output build/feature-verification/chat-browser
  ```

The creation-route host checks enter New project through its FAB and menu,
verify the profile default and generated location, save the proposed path, and
retain manual locations through name edits and delayed reads. They also cover
read failure/retry, cancellation, and the existing folder and edit journeys.
The native creation journey waits for the new project's row menu to become
reachable after keyboard dismissal before verifying edit and delete actions.

Removal checks use the production picker and confirmation, holding the default
folder read, mutation snapshot and write separately. They cover cancellation,
read/write failure and retry, immediate membership cleanup, draft preservation,
and profile retirement. The design suite inspects the assigned card and
confirmation at normal and enlarged text in both themes.
The Chats overflow checks enter through the row's trailing action button and
verify that its inherited icon styling cannot fade the filled confirmation glyph.

## Gotchas

Bot chats are hidden from the ordinary list unless Show automated chats is enabled. A completed row mutation and a successful background refresh are separate observations. Move and delete use a fresh owner-issued revision and execution generation; a concurrent turn or edit can refuse the action without changing the row. Delete retires the runtime through the same stock owner transaction that removes its history.
