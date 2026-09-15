# Proposal 001: Show the chat, event, and useful context in notifications

## Status

- Category: direction
- Priority: P1
- Effort: M
- Risk: medium (event identity, asynchronous delivery, content exposure)
- Planned at: `6d62aa1`, 2026-09-16, including existing uncommitted notification changes
- Status: IMPLEMENTED and verified, 2026-09-16
- Dependencies: none

## Intended experience

Owner refinement: make notifications rich but palatable and simple. Build one
layout with three broad categories. Additional event types should fit these
categories without gaining their own settings, interaction, or renderer.

- **Title:** chat name.
- **Body:** short status followed by a useful excerpt.
- **Secondary text:** connection/profile, using labels already available locally.
- **Expanded view:** more of the same excerpt.
- **Tap:** open the owning chat using its existing navigation flow.

Illustrative example:

```text
Wing · Home server / developer
Fix Android notifications
Reply ready · Added chat names and useful message previews.
```

Use native expanded text. Approximately 180 grapheme clusters for collapsed copy
and 800 for expanded copy are content budgets, not promised Android line counts.
An unnamed chat uses “Untitled chat”; routing always uses durable identity.

## Three categories, one presentation

| Category | Example body | Events mapped here |
| --- | --- | --- |
| Update | Reply ready · Added chat names and useful previews. | Final replies, side answers, background results, end of queued work |
| Input needed | Input needed · Deploy to staging or production? | Questions, approvals, secure-input requests |
| Work stopped | Stopped · The response was interrupted. | Interruptions and failures |

These are presentation categories, not a new backend state machine. The status
can say “Failed” for a confirmed error. A status-only transition uses “Chat
updated · Open the chat to see the outcome.” It must not invent a reply or
claim success. That small wording distinction is enough; no separate design.

Questions use question text; approvals use their description. Secure input uses
fixed copy: “Input needed · Open the chat to provide secure input.” Failures use
fixed copy unless a known structured reason is available. These few extraction
rules feed the same renderer. No batch counts, choice lists, task progress,
attachment inventories, or bespoke actions in the first version.

Side and background results use their own response excerpt, with the same
“Reply ready” template. This describes an available reply without declaring the
parent task finished. Queued work uses the same template when delivery occurs;
this change does not introduce a new queue notification policy.

## Essential behavior

1. Capture a small immutable notification value at the event source, before any
   asynchronous permission or history work: owning chat key, display labels,
   category, status text, preview, and event identity when available. Do not pass
   a mutable chat for the renderer to inspect later.
2. Extract text belonging to this event. Never borrow an older assistant reply
   to fill an empty preview. Normalize whitespace and Markdown; omit reasoning,
   code blocks, tool logs, transport wrappers, control characters, and URLs.
   When no usable text remains, use short factual copy such as “Open the chat to
   read the reply.” No model calls or content-fetch requests for notification text.
3. Known sensitive requests always use fixed copy. Never expose their values,
   raw commands, or raw exceptions. Pattern-based redaction of ordinary excerpts
   must not be presented as a guarantee that arbitrary prose contains no secrets.
4. Rich previews are the default. Replace the optional-title control with one
   **Show message previews** switch: off keeps the chat name and short status.
   Use private lock-screen visibility and generic public text, subject to Android
   settings. Do not add a separate app lock-screen setting or three preview modes.
5. Suppress notifications for the currently visible chat and keep event deduplication.
   Results must not replace pending input: include category in visible notification
   identity where necessary. Do not build a chat-summary store, unread counts,
   recent-event lists, or a full request tracking system for this change.
6. Tapping opens the right chat. Its existing UI displays the current request or
   result. No new message-level deep links, action buttons, inline replies,
   approval execution, or retry actions. Swiping an alert performs no server action.
7. Initial/reconnect snapshots are silent baselines. Missing data or lost
   connectivity cannot become a success notification. Existing delivery limits
   remain relevant; this proposal improves content, not backend coverage.
8. Implement this target directly. Do not add legacy defaults, setting aliases,
   old payload parsers or migration shims. Any compatibility requirement needs
   explicit user approval. Update privacy and notification docs with the defaults.

## Scope boundary

Ship chat name + useful excerpt + expanded text + the three categories. Keep
notification channels, monitoring ownership, and tap navigation outside the
redesign. Chat alerts use the wing icon; monitoring uses its separate link icon.

Custom grouping, distinct sounds by category, precise result/request navigation,
images, per-request lifecycles and special handling for every task type are
**deferred ideas, not acceptance criteria or a promised second phase**.

## Original implementation evidence (before this change)

- `lib/main.dart:304`: the callback is `onAttention: (chat, needsInput, [eventId])`.
  Around line 326 it chooses `Needs your attention` / `Finished working`; the
  body is `chat.title` only when `notificationTitlesKey == true`, otherwise
  `Tap to open the chat.`
- `lib/core/services/profile_workspace_controller.dart:277`: `ProfileAttention`
  accepts a mutable `ProfileChat`, a boolean, and optional event ID. This loses
  event-specific semantics. `_event` already distinguishes approvals, clarify,
  secure input, errors, and side/background deliveries. `_settle` around 4962
  calls `_notify(chat, failed, ...)`, so interrupted turns take completion copy.
- `_completeTaskDelivery` around 3738 has the exact task kind and result before
  passing only `false` to `_notify`. `_notify` around 4975 suppresses the selected
  visible chat. Snapshot reconciliation around 5114 knows only waiting/idle.
- `lib/core/services/turn_notification_service.dart:171`: the platform sink
  specifies icon/importance/autoCancel but no expanded style, grouping, actions,
  or explicit visibility. Its plain-data `TurnNotification` and injectable sink
  are useful existing testing seams; extend these with the new target contract.
- `gateway_clarify.dart`, `gateway_approval.dart`, `gateway_sensitive_prompt.dart`,
  and `side_question_delivery.dart` already model the relevant content.
- `docs/BACKGROUND_NOTIFICATIONS.md` documents connected-app delivery limits and
  silent baselines. `docs/DESIGN_SYSTEM.md` requires Studio settings controls and
  separate monitoring/chat iconography. `PRIVACY.md:21` currently promises
  optional titles only; that wording must change with the feature.

## Implementation sequence and boundaries

The implementation used `hermes-android/` (Flutter 3.44.0, Java 17, Android SDK 36).
The original working tree included unrelated edits in
notification sink, native monitoring, documentation, routing tests and QA; do not
overwrite them. Compare these excerpts with the live files before implementation.

1. Add typed notification event and pure presentation models under
   `lib/core/models/` and `lib/core/services/`. Add table-driven tests for the
   scenario and content contracts. Use the plain-data/recording-sink pattern from
   `test/turn_notification_service_test.dart` and `test/support/recording_turn_notification_sink.dart`.
   Verify: `flutter test test/turn_notification_service_test.dart` plus each new
   focused test file, all passing.
2. Replace the boolean callback in `profile_workspace_controller.dart` and its
   production/test callers. Capture completion text before history refresh and
   task content inside `_completeTaskDelivery`. Update all references found with
   `rg -n 'ProfileAttention|onAttention|TurnNotification\(' lib test integration_test`.
   Verify: `flutter test test/profile_notification_live_test.dart test/profile_notification_coverage_test.dart`, all passing.
3. Add expanded text and visibility to the platform sink; wire the immutable
   content through main.dart. Separate attention/result notification identities
   where they could collide. Use the existing scoped chat payload and navigation.
   Verify: `flutter test test/plugin_turn_notification_sink_test.dart test/app_notification_routing_test.dart test/notification_delivery_ledger_test.dart`, all passing.
4. Replace the title setting with the message-preview switch in
   `lib/core/screens/app_settings_content.dart`, matching Studio controls. Update
   the notification test action, relevant settings tests, PRIVACY.md,
   docs/PLAY_DATA_SAFETY.md, docs/BACKGROUND_NOTIFICATIONS.md and docs/TESTING.md.
   Verify: `flutter test test/app_notification_settings_test.dart test/startup_notification_permission_test.dart`, all passing.
5. Run `flutter analyze --fatal-infos`, `flutter test`, and then
   `flutter build apk --debug` sequentially; each must exit zero. Run the existing
   emulator notification fixtures described in docs/TESTING.md and
   docs/BACKGROUND_NOTIFICATIONS.md, adding checks for the new presentation.

In scope: the files above, notification-specific models/services/tests, and
callback consumers in lib/test/integration_test. No server patches, push service,
monitoring lifetime changes, native service redesign, payload format changes,
new action plumbing, or thumbnail downloads. Compare existing working changes
before editing; do not overwrite unrelated work.

## Required verification cases

- Three category mappings, including failed, interrupted and status-only events.
- Exact event excerpts for main/side/background responses; missing text never
  selects an unrelated historical reply.
- A new turn starts while an older event awaits history or permission: the old
  event's immutable content stays correct.
- Two identical names in different profiles/connections, untitled chat, and
  attention/result ID collisions.
- Preview switch, private/public lock-screen content, sensitive-input fixed copy,
  long Unicode/Markdown text, and empty/code-only content.
- Existing duplicate suppression, foreground suppression, silent baselines and
  ownership-aware tap tests continue passing.
- Emulator: expanded text, locked-screen behavior, older/newer alert taps,
  Home/background delivery and activity recreation using existing fixtures.

Done means targeted tests, `flutter analyze --fatal-infos`, `flutter test`, and
`flutter build apk --debug` pass; device fixtures demonstrate rendering and chat
routing; documentation describes the implemented defaults. Run tests and builds
sequentially. Record unavailable device checks rather than claiming validation.
Verification completed:

- `flutter analyze --no-pub --fatal-infos`: no issues.
- `flutter test --no-pub --concurrency=2`: 1,769 passed, 10 opt-in tests skipped.
- Final focused notification tests after the indented-code projection check: 16 passed.
- `flutter build apk --no-pub --debug`: normal app APK built successfully.
- API 36 emulator fixture: background posting, activity recreation, screen-off
  Doze delivery, monitoring stop/restart, rich title/excerpt/expanded text/scope,
  and native PRIVATE visibility all passed. Expanded notification visually checked.
  Tapping the rich notification opened its owning chat without an error.
- The shared notification fixture now answers session.resume; 17 focused coverage
  and routing tests passed after that fixture correction.
- The driver now waits for asynchronous Android notification posting/cancellation
  instead of asserting immediately when service state changes.

The emulator had no secure screen lock; native PRIVATE classification was checked,
not a claim about every lock-screen setting or OEM layout. The initial unrestricted
full test run was terminated; the complete two-worker rerun passed.

If event attribution requires unavailable backend data, use factual status-only
copy; do not add fetching or invent a result. Stop and report if implementation
requires expanding native scope or the live source invalidates these assumptions.
Future events should map to these categories and share the formatter. Add a new
category only when it changes what the user needs to understand or do.

## Platform references

- [Android expandable notifications](https://developer.android.com/develop/ui/compose/notifications/expanded): native big text, inbox, picture and messaging templates.
- [Android notification creation](https://developer.android.com/develop/ui/compose/notifications/create-notification): actions and lock-screen visibility.
