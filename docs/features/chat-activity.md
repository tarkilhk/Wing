# Inspect and supervise agent work

Open Activity during an answer, inspect tool results, answer a question or approval, and follow a child while the parent continues; retain delivered results afterward.

Feature ID: `chat-activity`.

## Sub-features

- `chat-activity.inspect` — Read tool requests and delivered results, with fixed durations for streaming runs closed by Reasoning and a live elapsed counter for the current run.
- `chat-activity.respond` — Answer the current question or approval. Live approvals in normal, bot and group chats share command-review content with notification review. The exact command starts visible; completed request receipts remain under collapsed Activity.
- `chat-activity.delegate` — Follow a child and retain its saved result.
- `chat-activity.tasks` — Follow the current task batch above the composer. Once every task is completed or cancelled and its response ends, read the batch in that response's Activity Tasks tab. Later rounds and replayed updates do not restore it to the composer.

## How to get to it (user POV)

Open Activity from a conversation. Inspect tools, requests and saved results. During active work open the Agents or Tasks tab, inspect a child, and return while the parent continues.

Swipe up on either Subagents/Tasks bar zone above the composer to open that
category at its compact height. Swipe upward again on the open bar or anywhere
in the drawer to maximize, or downward in the drawer to close. Diagonal swipes
follow their larger component: sideways switches pages,
vertical movement resizes or scrolls. At full height, rows scroll upward and back
down; continuing downward from their top closes the drawer. The small top handle
also toggles compact/expanded height on tap. Closing keeps the draft; reopening
by tap starts compact.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/profile_execution_activity_test.dart test/profile_live_execution_test.dart test/reply_duration_test.dart test/profile_live_work_route_test.dart test/profile_subagents_test.dart test/question_activity_projection_test.dart test/question_activity_test.dart test/gateway_approval_panel_test.dart test/notification_approval_review_test.dart test/profile_approval_queue_test.dart
  ```

- **Task handoff across chat surfaces:** the production conversation route checks four completed tasks through streaming, held history, the original saved Activity Tasks tab, draft retention and three later rounds in both themes at normal/enlarged text. The owner suites also cover working histories, child completion, cancelled tasks, hydration and unfinished work retained after a response.

  ```sh
  flutter test --no-pub test/profile_live_work_route_test.dart test/profile_execution_activity_test.dart test/bot_group_history_test.dart test/subagent_timeline_session_test.dart test/saved_activity_test.dart
  ```

- **Drawer gestures:** the shared dock and production conversation route exercise
  upward expansion and downward dismissal for both categories, fixed composer
  geometry and compact reopening. The dock suite also checks slow dragging,
  short flicks, cancellation, both bar zones, dominant diagonal direction and
  row scrolling/dismissal handoff in both themes at ordinary and enlarged text.
  The first upward swipe opens compact, matching tap height even for short
  single-category content; the next upward swipe maximizes.

  ```sh
  flutter test --no-pub test/profile_live_work_dock_test.dart test/profile_live_work_route_test.dart
  ```

- **Android `journeys`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py journeys --output build/feature-verification/chat-activity
  ```

## Gotchas

Streaming durations start at the preceding user message or Reasoning block; native reasoning boundaries use their first receipt time on the phone. Missing or reversed timestamps omit the interval. Historical results have no live controls. Completed children remain current only while their parent turn is active. Task batches with unfinished work remain current after a response; fully settled batches retire when their response ends, before history finishes loading. A request must belong to the displayed chat.
