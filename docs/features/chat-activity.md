# Inspect and supervise agent work

Open Activity during an answer, inspect tool results, answer a question or approval, and follow a child while the parent continues; retain delivered results afterward.

Feature ID: `chat-activity`.

## Sub-features

- `chat-activity.inspect` — Read tool requests and delivered results.
- `chat-activity.respond` — Answer the current question or approval.
- `chat-activity.delegate` — Follow a child and retain its saved result.

## How to get to it (user POV)

Open Activity from a conversation. Inspect tools, requests and saved results. During active work open the Agents or Tasks tab, inspect a child, and return while the parent continues.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/profile_execution_activity_test.dart test/profile_live_work_route_test.dart test/profile_subagents_test.dart test/question_activity_projection_test.dart test/question_activity_test.dart
  ```

- **Android `journeys`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py journeys --output build/feature-verification/chat-activity
  ```

## Gotchas

Historical results have no live controls. Completed children remain current only while their parent turn is active. A request must belong to the displayed chat.
