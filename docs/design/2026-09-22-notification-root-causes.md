# Root causes after the failed build 2327 live retests

**Subsequent investigation:** the actual phone trace identified an earlier
saved-chat guard preventing request hydration. It is fixed and reproduced before/
after on Android; see [the cached-chat investigation](2026-09-22-notification-cached-chat-investigation.md).
The first question's fixed-phone live pass remains pending; B already passed.

**Latest live result on build 2328:** both focused retests are finished:
**A failed again; B passed**, including read clearing and no resurrection after
restart. See [the live record](2026-09-22-notification-2328-live-results.md).
No desktop prompt is pending. Do not repeat A unchanged; its complete live cause
remains unresolved despite the fixed fixture race. Earlier preparation and
validation notes below are historical where superseded by this result.

The [build 2327 live failures](2026-09-22-notification-followup-live-results.md)
remain historical evidence. This investigation replaces the earlier confidence
based on tests that did not cover the actual response and navigation sequence.

## Evidence gathered before changing the fixes

- Reused the recorded phone notification/service trace and actual rendered chat
  evidence from the failed runs. The real structured batch was available after
  opening; the restored reply remained visible after reaching the answer/bottom.
- Read the retained phone Flutter log. It contained only renderer startup entries,
  not RPC or notification state transitions. Queried Loki for the Claw Hermes
  dashboard service during the exact test window; it also contained no useful RPC
  trace. Neither log is claimed to prove an unrecorded RPC sequence.
- Recovered the restored reply's native pending-intent focus. It is an `answer`
  focus without a message ID, matching the agreed latest-answer navigation case.
  The private session/connection identity stays out of this document.
- Verified latest stock Hermes upstream at
  `fde4997f580c3480798fdf9c7e92c0079d6e03d6`, particularly
  `tui_gateway/server.py`, `methods_session.py` and `methods_prompt.py`. No server
  source, configuration, policy or deployed version changed.

## A — New question consumed as a silent baseline

The old notification-coverage fixture returned `{}` for `approval.pending`.
Stock Hermes returns an `approvals` list, including an empty list when no approval
is pending. That distinction changes the controller's asynchronous behavior:

1. The unopened-chat transition resumes its real structured question.
2. Hydration starts the normal approval refresh and marks snapshot input quiet.
3. The notification path awaits a journal write before publishing the new request.
4. The empty approval result invokes `_changed()` while that write is pending.
   The question's content fingerprint is published as a silent snapshot.
5. The later explicit notification sees the same fingerprint and is deduplicated.
   The coordinator has only a quiet baseline, so Android gets no first notice.

Changing just the fixture to the stock empty-list response makes the previously
passing regression fail: expected a fresh alert, received `false`.

Reproduction:

```sh
flutter test --no-pub test/profile_notification_coverage_test.dart \
  --name 'first unopened batch' --reporter expanded
```

Red evidence: `/tmp/wing-cold-input-stock-red.log`. The fix publishes the validated
new request synchronously after hydration, before yielding to the journal write.
Deduplication and quiet reconnect behavior remain intact; newer live events and
navigation retain their existing guards. No repeat-alert or compatibility path
was added.

The isolated Android fixture uses the corrected stock response and never opens
its chat. `scripts/test_native_cold_notification.py` confirms one fresh native
notice with three questions, real question/options and Review, then monitoring
shutdown. It does not substitute for a new desktop-triggered run on the phone.

## B — Outgoing route hides the visible notification route

The chat-list screen and the notification-opened chat screen share a retained
controller. Both wrote one mutable `visible` flag. The incoming notification route
could set it true, followed by the outgoing list setting it false. The actual
answer was visible, but the read guard correctly refused a supposedly background
controller. Scrolling could not repair that ownership error.

The old tests missed the combined path: restoration stopped before a tap;
transcript tests mounted one view; routing tests supplied controllers without
WingApp's production read callbacks.

The new `restored_notification_read_test.dart` uses WingApp's real registry,
persisted notification state, normal chat-list navigation, native interaction,
history loading, visible transcript/bottom and native cancellation. Without the
fix, cancellation is absent and controller visibility is false. With the fix,
read cancellation succeeds and another cold launch cannot restore the read result.

Each route now owns its visibility claim. Covering or disposing a route releases
only its claim, so the outgoing list cannot hide the incoming chat. Answer
identity, latest-answer navigation and the read guard are unchanged.

The expanded native script verifies the actual Android sequence:
`restore → ordinary list → native notification tap → read clear → restart`, then
separately verifies a fresh swipe-dismissed reply does not return. The QA fixture
persists only dummy backend history so restart loads the same test answer.

## Validation

- Stock-response cold-input regression failed before the fix, passes after it.
- Real-route read regression failed before the fix; 19 focused routing/visibility
  tests pass after it.
- Actual Android 16 emulator: first unopened input content/count/Review, monitoring
  shutdown, silent same-ID reply restoration, native tap/read clearing, read state
  surviving restart and real swipe dismissal all pass.
- Static analysis is clean. Complete Flutter suite: **2,688 passed, 12 skipped**;
  **28 release-tooling tests** and source version check pass. Signed build 2328
  is installed on the phone, with package readback **1.0.1 / 23282**.
- The phone reconnected on the normal chat list after installation. The earlier
  stuck notice was already absent, so its tap/read path could not be verified
  directly. No cause is inferred for that absence. Both fresh live follow-ups
  remain required; see the [current status](2026-09-20-notification-test-status.md).

## Prevention

Notification fixtures must implement the stock response shapes for every call
made by the path under test, including empty collections. Route/read tests must
use production app callbacks and overlapping real navigation routes. A passing
coordinator or single-view test cannot establish end-to-end notification behavior.
Keep automated/native-fixture evidence distinct from actual Hermes/phone evidence.
