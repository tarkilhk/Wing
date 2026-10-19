# Chat with bots and coordinate discussions

Find a bot across saved instances, open its chat or group discussion, manage its identity, and view its desktop; take control only after ownership is confirmed, then hand it back.

Feature ID: `bots`.

## Sub-features

- `bots.chat` — Open the exact bot conversation.
- `bots.groups` — Read and manage a hosted discussion.
- `bots.desktop` — Observe passively and acquire or release input control.

## How to get to it (user POV)

Choose Bots in the drawer. Use the Bots and Groups tabs. Tap a name or preview for chat, an avatar for appearance, or the row menu for Bot settings and View screen. Long-press a profile icon in Chats for Bot Chat.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/bots_contract_test.dart test/bot_group_history_test.dart test/bot_screen_session_test.dart test/bot_screen_view_test.dart
  ```

- **Android `bots`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py bots --output build/feature-verification/bots
  ```

## Gotchas

Bot Chat and group discussions have different return destinations. Live desktop control needs a running stock desktop and a confirmed lease; fixture lease checks do not establish a real desktop session.
