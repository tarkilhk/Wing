# Dictate and hear replies

Choose device or Hermes processing, dictate into an editable draft and play a reply; cancel, recover a missing capability or failure, and prevent capture/playback conflicts.

Feature ID: `voice`.

## Sub-features

- `voice.dictate` — Finish or cancel into the correct draft.
- `voice.speak` — Start stop or interrupt reply playback.
- `voice.recover` — Handle permission capability and provider failure.

## How to get to it (user POV)

In App settings choose device or Hermes input/output. Tap the chat or group microphone to dictate into an editable draft, and use a reply playback action to hear it. Stop or cancel explicitly.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/profile_voice_test.dart test/hermes_voice_test.dart test/profile_voice_page_test.dart test/voice_arbitration_owner_test.dart
  ```

- **Android `voice`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py voice --output build/feature-verification/voice
  ```

## Gotchas

Offline recognition availability is an OS capability, not just a permission. Native offline samples do not prove live provider speech or human intelligibility. No additional charged provider calls are implied by this recipe.
