# Read and search conversation history

Open saved or streaming history, search older messages, page through a long conversation and return to the previous reading position.

Feature ID: `conversation`.

## Sub-features

- `conversation.read` — Reconcile live and saved messages.
- Normal chats, canonical Bot Chats, group discussions and bot working histories share the conversation frame and reading layout. Passive Recents cards use the same frame and composer presentation.
- `conversation.reading-mode` — Use a table’s full-screen icon to hide the composer and portrait context row without leaving the conversation. The same icon or Android Back restores it; drafts remain intact. Landscape puts title and scope in one header row.
- `conversation.search` — Find and open older content.
- `conversation.position` — Page and return without losing reading position.

## How to get to it (user POV)

Open a chat from Chats, Bots, Recents or a notification. Read older messages, choose Find in chat from its menu, open a result, then return to your reading position or Latest.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/profile_history_search_test.dart test/conversation_routes_test.dart test/conversation_reading_position_test.dart test/conversation_assembly_test.dart test/profile_row_actions_test.dart test/connection_diagnostics_test.dart
  ```

- **Android `journeys`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py journeys --output build/feature-verification/conversation
  ```

- **Android `transcript-expansion`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py transcript-expansion --output build/feature-verification/conversation
  ```

## Gotchas

Opening or tapping Latest does not mark a message read. Saved reading positions last until Wing restarts. Long-history host tests cover paging beyond the small Android fixture.

Automatic read-acknowledgement failures are logged in the phone's diagnostics
without a conversation warning. Failed acknowledgement still leaves the chat
unread for retry; explicit Mark as read actions retain their failure feedback.
The row-action viewport regression checks rejection, diagnostic output and later
successful acknowledgement in both themes at normal and enlarged text sizes.
