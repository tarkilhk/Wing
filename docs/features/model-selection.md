# Choose a model and reasoning settings

Browse provider/model choices, inspect supplied settings, apply the intended change and handle its confirmation or rejection in the captured profile.

Feature ID: `model-selection`.

## Sub-features

- `model-selection.choose` — Browse and inspect supplied model options.
- `model-selection.apply` — Confirm the captured model or reasoning choice.
- `model-selection.reject` — Retain the previous setting after cancellation or rejection.

## How to get to it (user POV)

Tap the short model name in the composer, or open model settings for the selected profile. Choose provider/model and reasoning or fast settings, then apply or cancel the pending choice.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/model_chooser_test.dart test/profile_model_edit_session_test.dart test/chat_model_confirmation_test.dart
  ```

- **Android `journeys`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py journeys --output build/feature-verification/model-selection
  ```

## Gotchas

Conversation model changes and profile defaults have different scopes. A selected picker row is not a confirmed backend change; handle an explicit confirmation or rejection.
