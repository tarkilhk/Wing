# Bring files into a conversation

Pick, capture, paste or share content, review it in the intended draft, cancel or remove it, and send only admitted content; restore staged work after interruption.

Feature ID: `attachments-and-sharing`.

## Sub-features

- `attachments-and-sharing.stage` — Review picked captured pasted or shared content.
- `attachments-and-sharing.cancel` — Remove or abandon only the intended draft item.
- `attachments-and-sharing.deliver` — Send admitted bytes once and restore staged work.

## How to get to it (user POV)

Use the chat attachment or camera control, paste supported content, or share to Wing from another Android app. Review the staged draft, remove or cancel an item, then Send.

Groups with bots on other instances accept text only. Their attachment control
explains the limit. Restored editable files remain removable; remove them before
a new send. A text-only Android share can still be staged, while a refused
file-bearing share remains available for another destination. Already-dispatched
uncertain messages keep their original files and exact Retry action.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/attachment_draft_service_test.dart test/profile_attachment_parity_test.dart test/home_share_review_test.dart
  ```

- **Image preparation:** exercise codec allocation refusal, JPEG restart,
  PNG output growth, metadata removal and WebP pixel/frame parity.

  ```sh
  flutter test --no-pub test/attachment_image_worker_test.dart test/image_codec_provenance_test.dart test/image_codec_confinement_test.dart
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

- **Cross-instance group admission:** the [Bots recipe](bots.md#driving-it-with-wing-harnesses)
  covers mixed-group preparation and text sending through Android controls,
  alongside the existing local-group attachment/picker flow. The focused
  `test/bot_group_peer_test.dart` and `test/bot_group_peer_view_test.dart` cover
  text-only sharing, retained editable files and immutable uncertain retries.
  `flutter test --no-pub test/shared_draft_review_test.dart` drives the production
  share review into a mixed group: text is acknowledged only after its exact
  draft is durable, while file refusal keeps the incoming share available for
  another destination. These mocked native-channel cases prove routing and
  acknowledgement ordering after intake; the Android `external-share` family
  owns the separate OS intake boundary.

## Gotchas

A file picker, external share and clipboard grant are separate OS entry points. A missing staged file must stop dispatch without discarding the newer draft. Its failed-file card remains actionable at the restored reading point; use Latest to inspect the transcript warning. Real camera/OEM behaviour needs its own device evidence.

An image can exceed processing limits even when its compressed file is small.
Dimensions, animation frames and transformed output also affect admission. A
refused image must leave the draft usable and must not become sendable content.

An upload failure or missing staged file shows a readable error beside that
attachment, with Remove still available. Failed transcript image previews keep
Retry available in the tile and gallery; the original attachment remains intact.
`test/composer_attachment_preparation_test.dart` and
`test/user_message_attachment_test.dart` cover these recovery surfaces.
