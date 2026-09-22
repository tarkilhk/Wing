# Build 2327 notification follow-up live retests

Phone: Galaxy S23 Ultra, Android 16, Wing 1.0.1 / Android version code 23272.
The user drives the same desktop Hermes chat; Codex operates the phone. Raw
captures remain private at `/tmp/wing-notification-followup-2026-09-22/`.

## A — First structured input before chat opening: FAIL

- Verified build 2327 and force-stopped/relaunched Wing. After the user unlocked
  normally, verified Claw Connected on the chat list. Test chat stayed unopened;
  no test notification was present initially.
- User sent the genuine WING-COLD-INPUT request: terminal sleep for 30 seconds, then one
  three-question structured batch (environment, color, output).
- 22:26:15 SGT: captured Watching 1 chat / 1 working and automatically sent phone Home.
- 22:26:56 SGT: monitoring stopped; no test notification was present. A separate
  native dump confirmed no active Wing notification, not merely a capture-title
  filter mismatch.
- User confirmed all three questions were pending on desktop. Returning only to
  the connected chat list showed Idle, without a notification. Opening the chat
  then revealed the actual Your input 1 of 3 form with Environment and choices.
- Selected Preview, Blue, Summary on the phone and confirmed each. Before timeout,
  the actual final reply was visible: `WING-COLD-INPUT selected values: Preview ·
  Blue · Summary.` No test request remains pending from case A.
- This fails first-request delivery/content despite the passing client-fixture
  regression. Do not count build 2327's unopened-chat fix as live-verified. No
  backend or app setting changes were made during this case.

## B — Unread reply restoration and read clearing: PARTIAL

Restoration itself passed; read clearing failed.

- Returned to the connected chat list after case A. User sent a terminal sleep
  for 30 seconds followed by the exact WING-RESTORE-REPLY. Monitoring started;
  capture sent phone Home automatically.
- 22:32:15 SGT: monitoring stopped and the exact reply arrived in notification
  ID 1495764829. It was unread in Wing.
- 22:32:32 SGT: saved its exact title, collapsed/expanded text and ID. Explicitly
  force-stopped Wing, verified Android removed the notice, then relaunched.
- 22:32:34 SGT: the same ID and text returned with Android flags
  `ONLY_ALERT_ONCE|SILENT`. Monitoring remained off. The connected chat list stayed
  visible and the notice remained unread. **Force-stop restoration passes.**
- Tapped the actual restored reply in the Android notification shade. Wing opened
  the correct chat with the complete latest answer visible. The notification
  nevertheless remained.
- Performed a full-bottom scroll. Fresh UI XML and screenshot confirm the entire
  final reply and bottom of the chat; the same native notice remained at 22:34:59
  and thereafter. This fails read clearing for a restored reply. Unlike the prior
  New activity observation, another bottom gesture did not clear it.
- Did not run the read-notice-stays-absent restart branch: its precondition failed.
  Do not call a swipe dismissal a read or claim that unrun branch passed.

## Final status

**Both planned retests finished: 0 fully passed, 1 partial, 1 failed.** There are
no further desktop prompts from this run. Case A's real questions were completed;
case B's final answer is complete. No settings, backend policies or credentials
were changed. The phone is left on Home with the stale case B notice retained as
failure evidence; capture is stopped.

Follow-up work:

1. Diagnose the real unopened-chat path: a genuine structured question is
   available on opening, but first notification is absent and the list shows Idle.
   The automated fixture passed but did not cover the observed condition.
2. Fix restored-reply read acknowledgment: restoration and destination are correct,
   but reading the complete answer at the bottom does not clear its notice.

Both require focused regressions using the newly observed conditions, then live
retests after a fix. The earlier build 2327 fixture/build validation remains true,
without overriding these live outcomes.
