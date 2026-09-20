# Notification live test results — 20 September 2026

Device: Galaxy S23 Ultra, Android 16, Wing 1.0.1 build 2323 (ARM64 23232).
The user drives the same test conversation on Hermes desktop; Codex operates
Wing through ADB and records device observations. Times below are Singapore time.
No backend settings, permissions, or approval policies were changed.

## LIVE-1: desktop work while Wing is foregrounded — FAIL

The user submitted: “Use a terminal tool to sleep for 45 seconds, then reply
exactly: WING-LIVE-1: First live test finished.” They confirmed that exact reply
completed. This run tests receipt/monitoring before relying on background delivery.

| Observation | Recorded result |
| --- | --- |
| Capture interval | 21:51:30–21:55:47; 80 device samples |
| Initial Wing screen | Connected Claw chat list, default profile; test conversation unopened |
| During desktop work | Chat list remained connected and labelled the test chat Working |
| Android monitoring service | Absent in all 80 samples |
| Monitoring notification | Never appeared |
| Reply notification | Same existing notification ID; retained a WING-N02 marker throughout; no WING-LIVE-1 marker |
| Backend completion | User confirmed the exact final reply; confirmation recorded at 21:54:35 |
| After completion | Chat list still showed Working, with its last-update label aging; old notification remained |
| Phone operations | Kept Wing foregrounded through completion, then inspected notification shade; did not open/read the answer |

Raw observations and the private screenshot are retained locally in
`/tmp/wing-live-notification-test/`; phone screenshots containing other apps are
not committed. Historical Android logs did not retain enough Wing lifecycle
information to reconstruct the earlier Round 2 run.

This failure reproduces while Wing is foregrounded. The earlier explanation
that background idle monitoring alone explains the result is insufficient.
The revised prompt's foreground prerequisite did not resolve this run.

## Diagnostic checks, not live passes

A focused controller test accepts working-state snapshots for a different
desktop runtime, but fails for an already-loaded idle runtime when its live
message-start event is absent: `hasActiveChats` stays false. This identifies a
client blind spot, but the original phone's event receipts are not recorded, so
it is not yet proof of the complete live root cause. Do not mark LIVE-1 fixed
until the same phone/desktop sequence passes.

## LIVE-2: after a diagnostic restart — PARTIAL / CONTENT FAIL

Installed signed build 2324 in place. Its only production-code changes are
temporary `[DEBUG-wing-live]` logs of event types, hashed runtime identifiers,
state counts and native monitoring decisions. No content/credentials are logged.
Both notification toggles and previews were enabled before installation.

The user ran the same 45-second operation with final marker `WING-LIVE-2`.
The native trace recorded:

- 22:04:47–48: global session-change event and a working runtime snapshot;
  controller reported active work; native start saw `visible=true`; service started.
- 22:05:40: the runtime became idle; a result notification appeared and the service
  stopped. Its body had no `WING-LIVE-2` marker. The global status path produced a
  generic update rather than the completed answer.
- 22:05:53: Home actually reached the phone. Despite being requested earlier,
  this was **after** completion, so background delivery is not established.
- 22:05:58: the profile event connection reported disconnected.

Restarting restored work detection; no functional fix was applied. This does
not establish that the original stale connection/state problem is resolved.
Before LIVE-3, the operator reopened Wing, opened the test chat once to establish
its live subscription (reading the result), then returned to the connected list.
The next Home action is automated on observing the watcher to avoid tool latency.

## LIVE-3: subscribed chat, then background — PASS for observed behavior

Same diagnostic build, with the test chat opened once before returning to the list.
The user ran the 45-second operation with final marker `WING-LIVE-3`.

- 22:08:40: Wing received `message.start` for its loaded test runtime; the native
  watcher started while the app was visible.
- 22:08:42: the observer automatically pressed Home.
- 22:09:34: Wing received `message.complete` while backgrounded.
- 22:09:35–38: the existing chat notification ID displayed `WING-LIVE-3`; the
  foreground service stopped after posting the result.
- 22:09:40: the profile event connection reported disconnected.

This establishes background delivery of the actual answer for an attached live
chat. It does not establish sound, lock-screen actions, or recovery after the
subsequent idle disconnection. LIVE-4 repeats after reopening only the chat list,
without reading the LIVE-3 answer or reattaching by opening the conversation.

## LIVE-4: loaded chat after idle reconnect — FAIL, cause captured

The user ran the same operation with `WING-LIVE-4` and confirmed completion.
Wing remained foregrounded on the connected list throughout; the automatic Home
step never triggered because the watcher did not start.

At 22:10:58, 22:11:00, 22:11:02 and 22:11:14, Wing received global session changes
and a **working** snapshot for the same runtime it locally held as **completed**.
Each reconciliation then reported `active=false background=0`. There was no
session-specific `message.start` or `message.complete`. At 22:11:51 the runtime
became idle again. The notification continued to display `WING-LIVE-3`.

The socket reconnects on foreground entry, but it reattaches only busy/selected
chats. A previously loaded chat reached from the list can therefore lose its
session-specific event subscription. Notification reconciliation then skips its
authoritative working snapshot solely because that chat is already loaded.
Together those behaviors suppress watcher startup and the replacement reply.

The regression test reproduces that sequence and fails before the fix. The fix
reattaches only a loaded, nonbusy chat newly reported as working/starting, using
the existing profile-checked `session.resume` with `omit_messages=true`. It does
not resume every idle chat, fetch full history, add polling, or extend monitoring.
Live events/navigation that overtake a resume response remain authoritative.

Stock Hermes at `2ed6387d87b4db091af2f05db32faab6e0dbb9a2` explicitly preserves
existing subscribers when a live transport reattaches; no backend change is used.
The regression and full suites pass after the change. Temporary trace statements
are removed from the fixed source and from signed build 2325.

## LIVE-5: fixed build after idle reconnect — PASS

Installed signed build 2325 (ARM64 versionCode 23252) in place. Opened the test
conversation once, returned to the list, went Home for eight seconds to allow
the idle connection to close, then reopened only the list. This recreates the
loaded-but-unsubscribed state from LIVE-4.

The user submitted the 45-second operation with `WING-LIVE-5`.

- 22:26:17: Android's monitoring service appeared; the observer immediately
  pressed Home automatically.
- 22:26:24–54: Wing remained backgrounded with monitoring active.
- 22:27:09: notification ID `1495764829` contained `WING-LIVE-5`; the monitoring
  service was absent. Wing remained backgrounded.

This verifies watcher startup and actual answer delivery after the formerly
failing reconnect. LIVE-6 leaves this answer unread and repeats after opening
only the list, to verify replacement of an existing notification.

## LIVE-6: unread answer replaced after another reconnect — PASS

At 22:27:37 reopened only the retained chat list, leaving LIVE-5 unread. The user
submitted the next operation with `WING-LIVE-6`. The requested test prompt said
45 seconds; inspection of the actual chat afterward showed a 30-second sleep.
The captured watcher/background interval still covers that operation.

- 22:28:36: monitoring restarted. LIVE-5 remained in notification ID `1495764829`.
- 22:28:37: the observer automatically pressed Home.
- Through 22:29:08: monitoring remained active and LIVE-5 stayed visible.
- 22:29:16: that same notification ID changed to `WING-LIVE-6`, with no second
  chat notification. The monitoring service stopped.

This verifies replacement after a second idle reconnect, without opening the
conversation between desktop turns. Samsung's group-summary notification
temporarily remained; it is separate from the chat result and the service.

After capturing replacement, tapped the actual LIVE-6 notification in Android's
shade. Wing opened the correct conversation with the exact latest answer visible:
“WING-LIVE-6: Latest reply replaced the previous result.” A subsequent Android
notification dump contained no Wing notifications. This checks notification
navigation and clearing when that answer is reached; it does not separately
measure the instant of clearing relative to rendering.

## Fixed-build automated validation

- Regression reproduced before the fix and passed afterward.
- Full Flutter suite: 2,661 passed, 12 skipped.
- Flutter static analysis: no issues.
- Signed ARM64 release built successfully; package, build 2325, release
  certificate and non-debuggable flag checked before installation.
- No temporary `[DEBUG-wing-live]` instrumentation remains in source.

These runs do not verify audible alerts, locked-phone approval actions, or every
scenario in the broader notification test prompt.

## Continued script coverage — build 2325

The user requested continuation of the saved 19-scenario script. Hermes remains
user-driven on desktop; the operator prepares Wing and captures Android evidence.
No real approval is counted without an actual backend request. Unsupported stock
tool capabilities will be recorded as blocked rather than simulated.

| Scenario | Current coverage / next check |
| --- | --- |
| 01 Reply and reading | Latest-answer tap/clear passed in LIVE-6; older-history visibility case remains |
| 02 Replacement and identical replies | Passed same-slot replacement and exact identical-text fresh update; audible sound unobserved |
| 03 Foreground behavior | Passed normal reply suppression and real question notification while chat visible |
| 04 Monitoring and interruption | Passed live summary, lock-screen delivery, real interruption and watcher shutdown |
| 05 Three questions | Text advancement and Review passed; missing unanswered count is a failure |
| 06 Approve once | Blocked: Smart auto-approved the safe probe; no approval request |
| 07 Deny | Blocked under current policy: no real safe approval generated |
| 08 FIFO approval queue | Blocked under current policy; concurrency also unverified |
| 09 Mixed input priority | Blocked under current policy; concurrency also unverified |
| 10 Swipe dismissal | Unchanged question stayed dismissed after reconnect and process restart; new-request branch not covered |
| 11 Long command and visual inspection | Approval-specific branch blocked under current policy |
| 12 Hidden previews and channels | Question privacy and restore passed; blocked-category notice/settings link and restore passed |
| 13 Device unlocking | Approval action branch blocked under current policy |
| 14 Offline action and stale request | Approval action branches blocked under current policy; not substituted with question Review |
| 15 Desktop resolution | N15 pending-question cleanup on reconnect passed; earlier N10 stale-list failure retained separately; watcher-active branch not covered |
| 16 Restart/reconnect | Idle reconnect/unread retention passed; dismissed pending question survived explicit process stop/relaunch |
| 17 Secure input | Blocked: Hermes reports no harmless generic secure-input tool; capability check complete |
| 18 Session scope | Blocked under current policy: no real safe approval generated |
| 19 Always scope | Blocked under current policy; no permanent grant attempted |

### Scenario 03: normal foreground reply — PASS

Kept the test conversation visible at its latest answer. The user requested a
15-second tool wait followed by the exact WING-N03 result.

- 22:33:56: monitoring started while the conversation remained visible.
- 22:34:18: monitoring stopped; no Wing notification remained.
- 22:34:20: UI inspection found the exact final answer, “WING-N03: Foreground
  reply received. Continue with the next test.”
- No chat completion notification was observed during the captured turn.

The attention-notification half is tested separately using scenario 05's real
structured question batch while the same conversation remains visible.

### Scenarios 03 attention / 05 batch questions — PARTIAL, count display FAIL

At 22:35:09, a real stock batch of three questions produced an attention-channel
notification while the owning chat was visible. Monitoring stopped while waiting.
The notification showed the first question and its backend-supplied choices.

Tapping the notification's actual Review action opened the correct question form
(`1 of 3`) and retained the pending notification. Answered Preview, then Blue,
then Summary through Wing's form. After each of the first two confirmations, the
same notification advanced to the next question and its choices; the form showed
`2 of 3`, then `3 of 3`. Final confirmation removed the pending question notice
and Hermes resumed work.

**Failure:** the expanded Android notification omitted the unanswered-question
count, both initially and after each answer. Its text/bigText contained only the
current question and choices; subText contained only `Claw / default`. The form's
progress indicator does not satisfy the required count inside the notification.

The phone rotated to landscape during inspection. Choice controls needed
scrolling back into view; that operator adjustment is not recorded as a product
failure. No phone rotation setting was changed.

### Scenario 06: Approve once — BLOCKED by current backend policy

Wing started monitoring at 22:41:21 and automatically went Home. Hermes reported
that Smart auto-approved the flagged recursive deletion of its freshly created
test child. A normal completion notification carried that BLOCKED result; no
approval notification was observed. The reported child was removed and its fresh
parent directory remained. These filesystem outcomes are Hermes-reported, not an
independent filesystem inspection by the phone operator.

No approval mode, allowlist or permission was changed. No riskier probe was
requested. Once/Deny/FIFO/mixed-approval/long-command/locked-approval/Session/Always
behavior cannot be established from this auto-approved operation. Those branches
remain blocked under the current test policy, not passed or proven unsupported
by the implementation. Question-based dismissal and resolution can still run.

User confirmed the same N06 outcome on desktop. Remaining disposable artifact:
`/home/tarkil/.hermes/cache/scratch/wing-notification-test-CZeiJPit` (parent only,
according to Hermes). No cleanup or additional approval probe was requested.

### Scenarios 10 / 16: dismissed question across reconnect and restart — PASS

N10 created a real single Summary/Checklist question after a bounded tool wait.
Monitoring started, Wing went Home, then the input notification appeared and
monitoring stopped at 22:44:04.

- 22:44:57: swiped away only the Wing question notification; no Wing notices remained.
- 22:45:01: reopened Wing's retained chat list. The owning chat showed Needs input;
  the unchanged notification did not return.
- 22:45:38: after explicit `am force-stop` followed by relaunch, Wing reconnected
  and still showed Needs input, with no restored notification.

No answer was submitted during these checks. This establishes dismissal
persistence for that pending question. Arrival of a genuinely new request while
the first remains unresolved was not generated; sequential replacement would
not establish that branch. Delivery during force-stop was not expected or tested.

### Scenario 15 derivative: desktop question resolution — stale list status FAIL

The user submitted Summary on desktop. Wing was connected on its chat list with
monitoring off. At 22:46:12–41, its row continued to show Needs input. After going
Home for eight seconds and reopening, the 22:47:22 check still showed Needs input.

Opening the owning conversation then displayed Hermes's actual final reply:
“WING-N10 resolved: you selected Summary; no further requests were created.” No
pending question form remained in that opened conversation. The prior chat-list
state was stale after desktop resolution, including a normal reconnect.

This does not establish failure of notification removal: the N10 notification
was deliberately dismissed earlier. A separate visible pending notification is
needed to test that branch. No duplicate answer or stale action was submitted.

The chat-list status was still Needs input immediately after opening and leaving
the conversation. A later observation at 22:50:38, after visiting app settings
and returning to Chats, showed Idle. The capture establishes delayed recovery;
it does not isolate which refresh or navigation caused it.

### Scenario 12: hidden question previews and Android category — PASS

Saved the original enabled preview setting, then disabled it in Wing. The user
created a real question containing the dummy marker PRIVATE BLUEBIRD and two
choices after a 20-second tool wait. Wing backgrounded while monitoring ran.

- 22:52:04: attention notification appeared; monitoring stopped.
- 22:52:44: notification text and expanded text were both `Input needed`, with
  a Review action. Neither the dummy marker nor choices appeared in those fields.
- 22:52:57: restored previews to their original enabled state. The same pending
  notification immediately displayed the real question and choices again.

Then opened Android's Input needed and failures category, verified it was
enabled, and temporarily disabled it. Wing displayed the blocked-category warning
and settings link. Following that link opened the exact disabled category. At
22:54:43 the category was re-enabled, its enabled state verified, and Wing's
warning disappeared on return. Both settings are restored to their original state.

Android removed the existing notice when its category was blocked; re-enabling
did not immediately recreate that old notice. No new backend event was generated
while blocked. Hidden direct approval choices could not be tested without a real
approval. Review presence was checked here; its navigation was exercised in N05.

### Scenario 02 continuation: identical final text

First turn delivered the exact body `WING-N02-B: Identical sample result. Open
Wing to read this result.` in notification ID `1495764829` at 22:58:02 (first
captured sample). Android recorded update time `1789916280875` and flags `0`.
Left it unread and returned only to the chat list for a second separately
submitted turn with exactly the same final text.

The second turn updated the same notification at 23:00:20, Android update time
`1789916418530`, flags `0`. However, an exact body comparison found Hermes omitted
the final full stop. This is another replacement pass, **not yet an identical-text
pass**. An initial operator statement of identical wording was corrected after
the exact comparison. A third turn is requested to match the second body exactly.

The third turn completed at 23:02:43 (first captured sample), using the same chat
notification ID and flags `0`, with new update time `1789916561612`. Exact body
comparison with the second turn succeeded: both omit the final full stop. This
establishes a fresh update for a genuinely new turn with identical final text;
the old notice remained while work ran, with no second chat-result slot.

### Scenario 04: monitoring and lock-screen delivery — PASS for captured behavior

The user requested a bounded 60-second tool sleep. At 23:03:38 the monitoring
service was observed; the operator backgrounded Wing and sent the phone to sleep.
At 23:04:24 Android reported the keyguard showing, and both Wing monitoring
records showed `Watching 1 chat` / `1 working`, using icon resource `0x7f07006b`.

At 23:04:46 the chat notification changed to WING-N04. At 23:05:13 Android still
reported `showing=true` and `secure=true`; the exact final answer was in the
notification and the monitoring service was absent. `inputRestricted=false` was
also reported, so this establishes delivery with the lock screen showing, not
an authentication challenge or approval-security guarantee. UI capture can wake
the display; continuous screen-off power behavior was not measured.

The user is asked to unlock normally before the interruption run. No PIN, trust,
screen-lock policy or other authentication setting was changed.

### Scenario 04: real interrupted turn — PASS

The user requested a 90-second tool sleep. Wing's watcher was observed at
23:07:17 and the observer sent the phone Home. While the wait was still running,
the operator asked the user to press Stop on Hermes desktop; the user confirmed
doing so.

At 23:08:15 the same chat notification showed `Stopped · The response was
interrupted.` and the monitoring service was absent. Its icon resource was
`0x7f07006e`, distinct from the monitor's `0x7f07006b`. The packaged resource table
maps the monitoring resource to `drawable/ic_stat_monitoring`. This exercised a
real stopped assistant turn, not a shell error or fabricated error message.

### Scenario 15: visible question resolved on desktop — PASS on reconnect

N15 produced a real question notification at 23:10:10 and monitoring stopped.
The user then submitted Summary on desktop and confirmed Hermes finished, while
Wing remained backgrounded.

- 23:11:14: the old question notification remained; the watcher was off. This
  delayed cleanup is permitted by the agreed monitoring lifetime.
- 23:11:16–20: after reopening only the chat list, the question notification was
  replaced by a generic outcome notice, `Open the chat to see the outcome.`
- The list showed Idle. No stale question or action remained in the notification.

This run passes the reconnect branch. It does not erase the earlier N10 stale
list-state failure, nor test watcher-active polling: one waiting question did
not sustain monitoring. The generic outcome wording is the known snapshot-only
content limitation when the completed answer event was not received.

### Pause requested

The user asked to finish only N15 and the N17 capability check tonight, then
continue remaining gaps tomorrow. Older-history reading is deferred. Both
temporarily changed notification settings have already been restored.

### Scenario 17: safe secure-input capability — BLOCKED

The user requested read-only inspection of Hermes's actually exposed tools,
without starting any secure flow or changing credentials/configuration. At
23:13:12 Wing delivered the reported result: no exposed stock tool provides a
harmless generic secure-input request. Available masked flows concern site-bound
credential saving/filling, vault unlocking, or real verification codes.

This is a runtime capability report, not a live secure-input UI pass. No secure
request was generated, no secret was entered, and no account or configuration
was modified. The capability check is complete; the UI scenario remains blocked.

## Tonight's stopping point and tomorrow's checklist

All 19 scenarios have a recorded disposition. Nine have live coverage; ten are
blocked under the current safe test conditions. Counting conservatively, four
scenarios passed their runnable checks (02, 03, 04, 12); five have partial coverage
or a recorded issue (01, 05, 10, 15, 16). Approval cases are blocked by the current
Smart policy, not established as unsupported by Wing. Audible sound is unobserved.

Tomorrow:

1. Reproduce and address the missing unanswered-question count in notifications.
2. Diagnose the stale Needs input list state after desktop resolution, especially
   the N10 sequence with a dismissed question and process restart. The later N15
   reconnect pass does not invalidate that earlier failure.
3. Finish the older-history/latest-answer read-clearing check from scenario 01.
4. Finish remaining restart cases and any safely available concurrent-input
   branches. Decide separately how to obtain real approvals; no policy changes
   or riskier approval probes have been authorized by this test script.
5. If real approvals become available, run Once, Deny, FIFO, mixed priority, long
   command/large-text layouts, unlocking, offline/stale actions, then Session and
   Always-confirmation/cancel last. Permanent acceptance still needs explicit
   instruction and a verified narrow scope.
6. Check audible alerts with someone listening. Clean up the recorded disposable
   parent directory through Hermes when requested; it remains listed above.

Phone remains on signed build 2325. No application code was changed during this
continued test session. Message previews and the Android attention category are
both restored to their original enabled states. No authentication settings,
backend policies, allowlists, or credentials were changed.

The user could not confirm hearing notification sounds. Audible behavior remains
NOT OBSERVED. Android's attention category was configured for Alert with default
sound Glitter and vibration enabled; settings alone do not prove audible output.


## Follow-up: fixes requested after the live-test pause

The user subsequently authorized fixing discovered bugs and saving a clean status.
The canonical handoff is now [notification test status](2026-09-20-notification-test-status.md).
The earlier stopping-point statement that no application code changed describes
only the live-test phase; this follow-up changes the client.

Two failures were reproduced before changes: missing question counts in Android's
actual renderer, and stale local question/activity state after desktop resolution.
Both now have regression coverage and client fixes. The count is included in
standard collapsed/expanded notification text. Existing global activity reads
refresh loaded pending requests through stock lightweight resume, and reconcile
known cached list activity without inventing completion from missing/unknown rows.
Delayed reads cannot discard a newer question. No additional polling is introduced.

Latest upstream stock Hermes was inspected at
`c1488ac947c9bc33fd65ec464548dc9d8edd6122`; the backend remains unmodified.
Automated results and deployment status are recorded in the clean handoff.
Live testing stays paused; phone results are not reclassified based on fixtures.


### Sound confirmation received

During the follow-up fix session the user confirmed: “I confirm sound, it works
as expected.” Audible behavior is now **PASS by user confirmation**. This
supersedes the earlier NOT OBSERVED entries; sound is no longer a pending check.


### Build 2326 deployed; live retests deferred

At the user's explicit request, installed signed ARM64 build 2326 with app data
preserved. Android package readback reports version code 23262, version 1.0.1,
updated at 23:41:26 on 20 September. Signing certificate matches the pinned
production certificate. Full Flutter suite: 2,670 passed, 12 skipped; analysis
clean; 28 release-tooling tests passed. Emulator rendering verifies 3/2/1 counts
and hidden previews; normal/200% text was inspected in both themes.

The user explicitly deferred live tests until tomorrow and requested the fixed
cases in the test script. Its new build-2326 section requires R1 count/privacy
checks, R2 dismissed-question/restart/desktop-resolution, and R2b resolution
followed by continued work. All three live retests are pending.
