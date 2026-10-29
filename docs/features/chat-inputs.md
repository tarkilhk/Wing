# Send, steer and revise work

Write and send, queue or steer a prompt, edit a queued or saved message, regenerate or fork an answer, and recover a draft or uncertain submission after interruption.

Feature ID: `chat-inputs`.

## Sub-features

- `chat-inputs.send` — Submit once and preserve newer unsent text. When leaving after Send, [conversation reading position](conversation.md) retains the sent-message boundary so the reply opens at its beginning.
- `chat-inputs.landscape` — Normal chats, Bot Chats and group discussions use the same responsive composer. Read with a one-row composer on landscape phones. Send/Stop stays visible; expand the controls to reach attachments, context and model options. With the keyboard open, the field and Send/Stop stay on one row; expanding dismisses the keyboard.
- `chat-inputs.queue` — Hermes owns the accepted FIFO; edits retain authored text and selected references and replace a still-queued message at the tail, steering transfers that exact admission to the current turn, and cancellation names its admission. Unsupported controls remain unavailable. Notes and continuation requests from the remote screen are queued independently and preserve the main draft, references and attachments, even when the text matches.
- `chat-inputs.revise` — Edit, restore or regenerate using revision-fenced saved row targets. Deep revision explains the number of later user turns removed; harmless last-turn regeneration remains immediate. Fork requires an idle source.
- `chat-inputs.clarify` — Use the explicit icon in a waiting question to answer with plain composer text. Slash commands, references and attachments retain their own submission semantics. A newer draft is never consumed by an earlier answer.

## How to get to it (user POV)

Write in the chat composer and Send. Hold the action button for steer or queue choices. Open queued work to edit it; use saved-message actions to edit or Restore and saved-answer actions to regenerate or fork.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/phone_reading_test.dart test/profile_composer_queue_test.dart test/profile_composer_actions_test.dart test/profile_prompt_reply_transport_test.dart test/profile_vault_server_request_test.dart test/canonical_session_protocol_test.dart test/composer_steering_delivery_test.dart test/saved_message_actions_test.dart test/native_prompt_controller_test.dart test/profile_question_delivery_test.dart test/profile_references_test.dart
  ```

- **Android `journeys`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py journeys --output build/feature-verification/chat-inputs
  ```

- **Android `queue-editing`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py queue-editing --output build/feature-verification/chat-inputs
  ```

## Gotchas

A lost acknowledgment retains the original submission ID and exact prepared payload before dispatch. Recovery may query that same idempotent input by replaying its exact request; it never creates a fresh input from matching text. Unknown execution requires explicit acknowledgment of that admission and generation, without rerunning it. Server-accepted work survives phone process death. Local upload and unsent draft preparation remain on the phone. Secret input must not enter durable draft/history storage. Provider generation needs separately authorized disposable QA state.
