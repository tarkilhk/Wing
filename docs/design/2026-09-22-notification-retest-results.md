# Notification live retests — 22 September 2026

Phone: Galaxy S23 Ultra; Wing 1.0.1 build 2326 (Android version code 23262),
verified through package readback. The user drives the same desktop Hermes chat;
Codex operates Wing and records observations. No backend policy changes.

**Finished: 3 passed, 1 partially passed, 1 failed.** No source code or backend
configuration changed. Previews restored to enabled; capture stopped; phone left
on Home. Runs 1 and the first attempt at run 2 expired; run 2 was repeated with
an explicit NOW cue and the user confirmed the actual desktop submission.

Five runs (run 5 used an available unread result before runs 3 and 4):

| Run | Coverage | Result |
| --- | --- | --- |
| 1 / R1 | Question counts 3 → 2 → 1; hidden-preview count privacy | PARTIAL: rendering/privacy pass; first background notice generic until chat opened |
| 2 / R2 | Dismissed question, process restart, desktop resolution; stale list badge | PASS on STALE-2 repeat: actual desktop Summary cleared list automatically after dismissal/restart |
| 3 / R2b | Desktop resolution followed by continued work and monitoring | PASS: input cleared, watcher resumed, exact reply delivered, watcher stopped |
| 4 | Older-history versus latest-answer read clearing | PASS for agreed full-bottom rule; New activity alone needed an extra scroll |
| 5 | Unread reply across process restart/reconnect and read clearing | FAIL: unread reply not restored after explicit force-stop/relaunch; tap/read branch unavailable |

These revisit the original 19 scenarios; they do not add five new scenarios.
Other blocked/concurrent-input gaps remain tracked in the
[clean status](2026-09-20-notification-test-status.md). Sound was already confirmed
working by the user and does not require another dedicated run.

Raw captures are private and stay outside Git at
`/tmp/wing-notification-retest-2026-09-22/`.

## R1 observations

- 21:16:22 SGT: watcher started; capture automatically sent phone Home.
- Initial attention notification ID 1495764829 said only `Open the chat to
  continue.` No count or Review action. Opening it revealed a genuine three-question
  batch. By 21:19:04 its collapsed/expanded text both displayed `3 questions` and
  the first question/choices. Initial unloaded-chat content is a separate gap.
- Selected Preview on phone: 21:19:48 both text fields displayed `2 questions`
  with the color question. Selected Blue: 21:20:12 both displayed `1 question`
  with the output question. Same notification ID throughout. Count rendering
  regression passes once the request is loaded.
- While navigating Settings, the request expired. The final Hermes reply at
  21:22 states: `WING-RETEST-COUNT incomplete: Preview · Blue · output unanswered.
  The structured batch timed out; no value was inferred.` This is not evidence
  of a privacy/count regression. Hidden-preview count and final user submission
  are not passed by this run. Previews were restored to enabled.
- Carry the pending-count privacy check into R2, before its dismissal/restart.

## R2 setup and carried privacy check

- The next question arrived directly with `1 question`, real question/choice
  text and Review. Unlike R1's first notice, no opening was needed for content.
- Hidden previews retained `1 question` in both collapsed/expanded fields and
  replaced private content with `Input needed`; question label and choices were
  absent. Previews were immediately restored and verified enabled. This completes
  the pending-count privacy check carried from R1.
- Swiped away only the test notice, explicitly force-stopped Wing, and relaunched.
  Chat list reconnected and showed Needs input; no test notification returned.
- Asked the user to submit Summary on desktop; waiting on automatic list cleanup.

### R2 timed out; cleanup observed, desktop-answer branch not passed

- No desktop-answer confirmation arrived. At 21:30:42 the watcher restarted,
  exactly around the request’s five-minute expiry. At 21:30:52 it stopped and
  the untouched connected chat list showed Idle instead of Needs input.
- The new reply notice says `WING-RETEST-STALE unanswered: the structured request
  timed out before selection; no further request was created.` Therefore this
  proves automatic timeout cleanup after dismissal/restart, not a desktop-answer
  run. That specific branch must be repeated while the user is ready to answer.
- Reused this unread real outcome for planned run 5, avoiding an unnecessary
  extra Hermes turn while waiting for the user.

## Run 5 — unread reply restoration after force-stop: FAIL

- At 21:32:06 the real unread timeout outcome was present in reply notification
  ID 1495764829. Wing was on its chat list; the reply had not been opened/read.
- Performed Home/resume, explicit `am force-stop com.tarkilhk.wing`, then
  `am start` and allowed reconnect. The list showed the test chat Idle.
- Capture shows the notification absent at 21:32:10 and still absent through
  21:32:50 with Wing connected on its chat list. No read or swipe dismissal was
  performed on this reply. This fails the explicit force-stop/relaunch restoration
  check; it does not establish loss on ordinary backgrounding or every process
  death mode. Tap-to-read clearing could not be exercised after its disappearance.
- Preserve this as a separate finding from the two build-2326 fixes. No source
  change was made during the live tests.

### R2 controlled repeat — PASS

The user requested an unmistakable in-chat action cue. Subsequent timed decisions
use **NOW: select Summary on desktop**, with the question card only supplemental.
A first setup attempt hit UI-dump contention before any dismissal; stopped periodic
UI dumping, retained notification/service capture, and retried preparation.

At 21:37:12 Wing was reconnected on its list with Needs input after dismissal
and explicit force-stop/relaunch; the dismissed notice stayed absent. Gave the
NOW cue. The user confirmed Summary submitted. Monitoring ran at 21:37:35 and
stopped at 21:37:41; by 21:37:59 the untouched connected list showed Idle. This
was an actual desktop answer, not expiry. No manual refresh, Settings visit or
chat opening caused that initial status change.

## R2b / run 3 — PASS

At 21:40:13 the connected list showed Needs input and the real question notice
remained visible. Gave the explicit NOW cue; the user confirmed Summary submitted.
At 21:40:51 monitoring resumed and capture sent the phone Home. At 21:41:10 the
monitor showed `Watching 1 chat` / `1 working`; the question and choices were gone
(the slot temporarily held a generic outcome notice). At 21:41:35 the monitor
stopped and the same chat notification ID held the exact result:
`WING-RETEST-CONTINUE: Summary prepared. Open Wing to read the result.`

## Run 4 — PASS for the agreed full-bottom rule; navigation detail recorded

- Positioned the chat in older history before the turn, then verified its Latest
  control again after the desktop turn started. At 21:44:05 backgrounded the phone
  while work was still running. The new reply arrived at 21:44:42–45.
- Reopened Wing normally, without tapping the notification. It retained older
  history (N17 and the earlier count test visible); the new answer was not visible
  and its notification remained. The shortcut label changed from Latest to
  New activity, so the capture script was corrected to recognize the real label.
- Tapped New activity. The full new answer was visible, but its notification
  remained. A subsequent shade UI dump could not obtain idle state and returned
  a stale XML file; that dump is not used as shade evidence. Android's active
  notification list independently confirmed the notice was still present.
- Scrolled fully to the bottom. The notification then cleared. A screenshot
  confirmed the actual final answer and end-of-chat position; the final native
  notice capture was empty. This passes the user's accepted bottom-of-chat
  alternative. Record a UX follow-up: New activity alone did not satisfy that
  bottom/read condition, despite bringing the answer into view.

## Remaining findings and next work

1. First question notification for the initially unopened/unloaded chat was
   generic until opening it, despite a real structured batch being pending.
   Counts and useful content worked for subsequent loaded-chat requests.
2. Explicit force-stop/relaunch did not restore an unread reply notification.
   This is a restoration gap, not proof of a problem with ordinary backgrounding
   or every process-death path. No read or dismissal explained the loss.
3. Review New activity scrolling/read acknowledgment: reaching the visible answer
   via the shortcut did not clear; an additional full-bottom scroll did.

The two build-2326 fixes have live evidence: count rendering/privacy and actual
post-restart desktop resolution both work under the recorded conditions. Do not
turn the partial initial-notification run into an unqualified whole-scenario pass.
Keep the remaining stock approval/secure-input/concurrency limits from the main
status. All temporary test capture processes are stopped. No further request is
pending from these five runs.
