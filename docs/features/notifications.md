# Respond and return from notifications

Receive a reply or input request, act on or open the exact conversation, then read or dismiss it without reviving a settled or dismissed notice.

Feature ID: `notifications`.

## Sub-features

- `notifications.route` — Open the exact notification owner.
- `notifications.act` — Answer a supported request without duplication. Command review uses the same exact-command and request-details content as normal, bot and group chats, while keeping the selected notification approval scope explicit.
- `notifications.settle` — Keep read dismissed and restored notices consistent.

## How to get to it (user POV)

While Wing monitors work, receive a reply or input request in the Android notification shade. Open its exact chat, respond through supported actions, then read or dismiss the notice.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/notification_answer_visibility_test.dart test/group_notification_session_test.dart test/profile_notification_coverage_test.dart test/app_notification_routing_test.dart test/notification_approval_review_test.dart
  ```

  The queued native cold-tap case includes the notification device fixture's
  restart setup. It must preserve the captured profile/chat, reuse both existing
  chats and display the answer above the remembered workspace route.
  Restored profiles must also admit a later message and publish its reply
  without changing the selected chat during recovery.

- **Android `notification-actions`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py notification-actions --output build/feature-verification/notifications
  ```

- **Android `notification-restore`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py notification-restore --output build/feature-verification/notifications
  ```

- **Android `notification-counts`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py notification-counts --output build/feature-verification/notifications
  ```

- **Android `notification-cold`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py notification-cold --output build/feature-verification/notifications
  ```

## Gotchas

Use only the owned QA package. Android notification permission and battery policy are prerequisites. Opening, reading and dismissing are different actions; verify restore and cold entry separately.
