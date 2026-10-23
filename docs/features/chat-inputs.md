# Send, steer and revise work

Write and send, queue or steer a prompt, edit a queued or saved message, regenerate or fork an answer, and recover a draft or uncertain submission after interruption.

Feature ID: `chat-inputs`.

## Sub-features

- `chat-inputs.send` — Submit once and preserve newer unsent text.
- `chat-inputs.landscape` — Normal chats, Bot Chats and group discussions use the same responsive composer. Read with a one-row composer on landscape phones. Send/Stop stays visible; expand the controls to reach attachments, context and model options. With the keyboard open, the field and Send/Stop stay on one row; expanding dismisses the keyboard.
- `chat-inputs.queue` — Edit or cancel a queued follow-up. Notes and continuation requests from the remote screen are queued independently and preserve the main draft, references and attachments, even when the text matches.
- `chat-inputs.revise` — Edit restore regenerate or fork saved work.

## How to get to it (user POV)

Write in the chat composer and Send. Hold the action button for steer or queue choices. Open queued work to edit it; use saved-message actions to edit or Restore and saved-answer actions to regenerate or fork.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/phone_reading_test.dart test/profile_composer_queue_test.dart test/profile_composer_actions_test.dart test/profile_prompt_reply_transport_test.dart test/profile_vault_server_request_test.dart
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

A lost acknowledgement is uncertain delivery, not permission to resend. Secret input must not enter durable draft/history storage. Provider generation needs separately authorized disposable QA state.
