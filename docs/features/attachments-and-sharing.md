# Bring files into a conversation

Pick, capture, paste or share content, review it in the intended draft, cancel or remove it, and send only admitted content; restore staged work after interruption.

Feature ID: `attachments-and-sharing`.

## Sub-features

- `attachments-and-sharing.stage` — Review picked captured pasted or shared content.
- `attachments-and-sharing.cancel` — Remove or abandon only the intended draft item.
- `attachments-and-sharing.deliver` — Send admitted bytes once and restore staged work.

## How to get to it (user POV)

Use the chat attachment or camera control, paste supported content, or share to Wing from another Android app. Review the staged draft, remove or cancel an item, then Send.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/attachment_draft_service_test.dart test/profile_attachment_parity_test.dart test/home_share_review_test.dart
  ```

- **Android `file-transfer`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py file-transfer --output build/feature-verification/attachments-and-sharing
  ```

- **Android `external-share`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py external-share --output build/feature-verification/attachments-and-sharing
  ```

- **Android `clipboard`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py clipboard --output build/feature-verification/attachments-and-sharing
  ```

## Gotchas

A file picker, external share and clipboard grant are separate OS entry points. A missing staged file must stop dispatch without discarding the newer draft. Real camera/OEM behaviour needs its own device evidence.
