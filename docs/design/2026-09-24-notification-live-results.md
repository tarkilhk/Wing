# Remaining notification live tests — 24 September 2026

## Session in progress

Physical Galaxy S23 Ultra, Android 16, Wing 2329 (1.0.1 / 23292).
The two earlier bug-fix retests remain passed. Original ledger at session start:
7 passed, 2 partial, 10 blocked; no new scenario result yet.

The user explicitly authorized temporarily changing the test profile from Smart
to Manual and using a second disposable chat for independent waiting work.

**Temporary change performed (restoration recorded below):** Claw / default approval
mode was confirmed `smart`, changed through Wing administration to `manual`,
and Save confirmed. Timeout (300 seconds), command allowlist, and connector
reload option were left unchanged. No permanent permission is authorized.

## N06 — Once: failed on 2329

- 11:05:22 SGT: Watching 1 chat / 1 working appeared; observer sent phone Home.
- 11:05:53: real approval notification arrived, ID 1495764829; watcher stopped.
  Expanded content showed the exact print-only script and Once, Session, Always,
  Deny controls.
- 11:07:39: UI automation tapped the actual Once control. Android activity logs
  confirm NotificationActionActivity launched and finished. The request and
  notification remained pending; no visible submission-error text appeared.
- User confirmed desktop still awaited the approval and supplied a screenshot
  of the same script. No desktop decision or permanent permission was submitted.
- Later attempted notification-body navigation has no matching activity launch
  evidence; do not classify that tap as a proven navigation failure.
- Around 11:10: Hermes timed out the request. The chat explicitly reported
  zero tool calls and no execution. This is a Wing action failure, not a
  backend capability block. No in-chat decision could be tested before expiry.
- Opening Wing recovered current state; timeout completion appeared, then the
  latest reply was read. An unrelated working chat appeared in monitoring;
  this is not the controlled two-chat cleanup test.

Original ledger is now 7 passed, 2 partial, 1 failed, 9 blocked.
Do not run the same dependent approval buttons repeatedly without diagnosis.

Private captures are in `/tmp/wing-notification-remaining-2026-09-24`; they are
not repository artifacts.

[Current source capability study](2026-09-24-notification-remaining-capabilities.md).

At approximately 11:13 SGT, Smart was restored through the same default-profile
editor. Save confirmation and readback showed `smart`; other policy fields
remained unchanged. No approval request remains pending from N06.

## N15 — Desktop resolution while monitoring is active: pass

- Phone remained on Nova Home after 11:13:16; no Wing foreground reconnect
  occurred between request delivery and desktop resolution.
- By 11:14:24 the exact WING-N15-POLL question/choices were in the input
  notification. Monitoring showed 1 needs input and 2 working.
- Other existing work already kept monitoring active, so the authorized extra
  disposable chat was unnecessary and was not created. No action was taken on
  those other chats.
- Explicit NOW cue was given, user submitted Summary on desktop, and by
  11:14:53 the same test-chat notification contained the selected-value reply.
  Monitoring continued with 2 working; Home activity was confirmed.
- Pass for the previously unobserved background-cleanup behavior while the
  watcher was already active. These system observations do not distinguish a
  timer reconciliation from streamed resolution/completion events; do not claim
  exclusive proof of the timer path. They also do not prove profile isolation.

Ledger after N15: 8 passed, 1 partial, 1 failed, 9 blocked.

## N17 — Secure input: remains blocked

The deployed assistant first reported browser_vault_enter_code and browser_exec
available, proposing a local file. Current stock normalize_origin requires a
host, so the real test prompt specified an inert loopback HTTP page instead.
The assistant then declined the flow as unsupported for a local dummy page.
It reports no file, server, browser tab, input request, or setting was created.
Only its bounded sleep ran. This is an ungenerated live test, not an observed
secure-input API error or proof that upstream rejects loopback origins.

Repeated Live updates interrupted states were visible in Wing while HTTP chat
reads still worked. Retry connection did not clear the state immediately. A
data-preserving force-stop/relaunch recovered Connected, but interruption
returned during N17. This is additional diagnostic evidence, not yet a proven
cause of the ignored Once action.

## Diagnosis discipline after N06

A new isolated widget reproduction through NativeNotificationSink and WingApp
passes with a connected request and fails when a live disconnect has marked the
chat reconnecting: no decision and no request-specific error. A trial recovery
patch made that constructed case pass, but **does not prove the phone cause**.
The trial patch was removed after the user explicitly required log-based root
cause evidence. Both patch and reproduction are retained privately for research.

Production logic remains unchanged. Temporary tagged diagnostic instrumentation
is being built to trace Android delivery, Dart handler guards, exact-request
validation, RPC acceptance/errors, and connection recovery. No command text,
credentials, or raw request payloads are logged. Original signed 2329 APK is
preserved privately with its verified original SHA256 for restoration.

At 11:31 SGT, signed diagnostic version `1.0.1-diag-n2409 / 23292` was
installed without clearing data. SHA256:
`f248a76560d17b59cba06012ce9e9a587125262689d856d2cc2df1527ebd626e`.
Only temporary tracing differs from baseline; speculative recovery changes
were reverted. Static analysis passed. Tagged connection events are visible
in phone logcat. **Manual was enabled again for the trace; restore Smart and
remove/replace the diagnostic build before concluding.**

### First diagnostic trace and foreground comparison

- The initial trace setup backgrounded Wing when unrelated work was active;
  that work ended before the next desktop prompt, stopping the watcher. This
  was an operator prerequisite miss, not a new notification failure. Automatic
  backgrounding is now gated on the exact test row being Working plus Android
  `isForeground=true`, not just any watcher activity.
- 11:33:43: actual socket disconnect. Subsequent reconnect attempts logged
  `_ClientSocketException`. Android netpolicy independently reported Wing UID
  10356 `blocked=APP_BACKGROUND`, `effective=APP_BACKGROUND`; no foreground
  service was running. Foreground entry reconnected successfully. No policy,
  battery, firewall, or network setting was changed.
- WING-TRACE-ONCE was pending in the chat but had no newly delivered notification
  in this invalid setup. It was approved Once **inside the chat**, as a path
  comparison, at 11:37:55. Backend request.answer returned status=ok 31ms later.
  This does not pass the notification-button scenario.
- The assistant's final prose incorrectly said no approval had been requested;
  actual Android form and accepted RPC trace are the evidence of the approval.
- TRACE-ONCE-2 is being prepared with the corrected foreground prerequisite.

### Actual root-cause trace (TRACE-ONCE-2)

Correct prerequisite was captured at 11:39:19: exact test row Working and native
monitoring isForeground=true before Home. The real approval arrived at 11:40.
The monitoring service subsequently stopped, the socket disconnected at
11:40:30, and reconnect attempts failed.

At **11:43:53**, a visually verified Once tap produced this narrow trace:

```text
native.deliver locked=false engine=true
native.route choice=once review=false
native.interact ready=true channel=true
action.enter choice=once review=false
action.parsed kind=approval target=924418150
action.credentials.end found=true
action.owner chat=true opening=false offline=false status=reconnecting request=924418150
action.return.unready
native.interaction.completed
```

The exact approval identity matched. No approval RPC followed: the handler's
reconnecting guard returned silently. The request later timed out with zero
execution. This is real phone evidence for the earlier constructed failure,
not an inference from a passing fixture. The native Activity also finishes
immediately after dispatch in the existing implementation; recovery must be
tested with an Activity lifetime that covers the asynchronous decision rather
than assuming a retained Flutter engine grants foreground network access.

**Smart restored and read back after the trace.** No test approval remains
pending. No permanent grant, battery or network-setting change was performed.
Diagnostic build is still installed pending the verified replacement.

Android documents that background resource restrictions can block networking
until the app is foreground: [background restrictions](https://developer.android.com/develop/background-work/background-tasks/bg-work-restrictions).
The separate Android netpolicy capture identifies APP_BACKGROUND on this phone.

### Fix and automated verification (2330)

- Removed the notification handler's silent disconnected-state return. The
  controller performs one bounded recovery for the explicit tap, joins an
  existing reconnect when necessary, then rechecks runtime and request identity.
- Connection health is checked separately from the chat label: a concurrent
  pending-request refresh can restore the Needs input label while offline.
- Failed recovery retains the exact request with the existing unconfirmed
  decision message. A late reconnect never replays the permission choice.
- Android dispatch now starts after the action Activity resumes and keeps that
  Activity alive until the Dart interaction completes. A retained Flutter engine
  alone does not establish foreground network eligibility.
- Regression was red on baseline via the production WingApp method-channel
  callback. Tests cover successful recovery, failed recovery, replacement during
  recovery, joining an in-flight reconnect, and timeout with no later replay.
- Affected suites: **74 passed**. Full suite: **2,704 passed, 12 skipped**.
  Static analysis: no issues. Source contains no diagnostic tracing.
- Isolated Android 16 QA package: a real Once button kept
  NotificationActionActivity top-resumed while a fake backend acknowledgement
  was deliberately withheld. Exactly one matching decision was recorded; only
  after acknowledgement did the request clear and Android return to Home.
- Isolated outage test: actual Once tap sent no additional decision, retained
  the request and rendered **Decision not confirmed · review or retry**. The
  Activity finished. The rendered UI hierarchy is the evidence; custom-view
  text was not exposed by the notification-service text dump.
- These are automated/isolated checks, **not a live N06 pass**. The next real
  phone retest must wait until monitoring stops and the socket has gone idle
  before tapping Once. All wider live approval scenarios remain outstanding.

Clean release **1.0.1 / 23302 (source build 2330)** installed on the phone
without clearing data. Production package, signing certificate, ARM64 ABI and
non-debuggable status verified; installed version read back. SHA256:
`193e98f9de5e8e6aa567172332fc5f23b099172f843beb2a7b46536193c88778`.
The diagnostic build has been replaced and temporary log collectors stopped.
Phone opens the connected Claw/default chat list. Real N06 retest pending.

12:08 SGT: fix committed/pushed as `adc4245`. For the next controlled real
N06 retest, the authorized temporary **Manual policy is enabled again on
Claw/default and read back**. Timeout remains 300; allowlist unchanged.
**Restore Smart after this pending retest**. No new desktop request yet.

### WING-ONCE-2330: live Once accepted; idle recovery not exercised

- Real approval arrived at 12:11:10 while Wing was on the connected list. The
  exact Working row was not captured: the observation moved from Idle to Needs
  input. The phone was backgrounded only after the real approval was present.
- Other real chats kept the foreground watcher active throughout, so this run
  cannot establish recovery from Android's background network restriction. No
  unrelated task was stopped and no phone network/battery setting was changed.
- 12:13:42: visually verified Once tap on the exact print-only
  `WING-ONCE-2330` approval. Android returned to the launcher.
- By 12:13:48 the input notification was replaced, under the same notification
  ID, by the assistant result reporting that the script ran and printed the
  marker. The monitoring summary dropped the approval count. The pending
  approval had remained unchanged for over two minutes before this tap.
- Hermes's final prose labels this auto-allowed/BLOCKED. That label conflicts
  with the actual captured pending approval and subsequent phone-tap sequence;
  it is not evidence that no request existed.
- **N06 live Once button: PASS on 2330 with monitoring active.** The separate
  real-phone idle/disconnected recovery regression remains pending. Automated
  recovery and isolated Android lifecycle/error checks already passed.
- Manual remains temporarily enabled for the continuing authorized approval
  test batch; restore Smart when that batch ends.

### WING-DENY-2330: live Deny passed

- 12:16:40: exact test chat Working and foreground monitoring captured before
  Home. Real print-only approval appeared by 12:17:01.
- 12:18:44: visually verified native Deny tap on that exact command.
- By 12:18:50 the same notification slot changed to the final result: Wing
  approval denied, script did not run, no retry or substitute tool used.
- **N07 PASS on 2330.** Other work kept the foreground service active; current
  Android netpolicy showed effective=NONE for Wing, so this is not the separate
  disconnected-recovery regression. No scope grant was made.
- Manual remains temporarily enabled for the continuing approved test batch.

### WING-FIFO-2330: queue advancement passed; second decision timed out

- 12:20:45: exact test chat Working and foreground service captured before Home.
- By 12:21:20, **two real approvals** shared notification ID 1495764829,
  with absent-a at the head. This directly establishes simultaneous pending
  requests, despite Hermes's later prose incorrectly claiming no queue existed.
- Long paths were truncated in the notification. Once opened the correct chat
  and full-command review dialog; no grant occurred before confirmation.
- 12:24:13: confirmed Once for absent-a. By 12:24:16, the same notification
  showed **one approval**, now absent-b. The first command completed as the
  intended no-op, and the second remained unresolved.
- 12:25:52: tapped the second notification's Deny. Long-command review opened
  with absent-b. Confirmation at 12:26:23 was too late; Hermes reported its
  approval had timed out and it did not run. This was an operator timing miss.
- **N08 partial:** real simultaneous queue and 2→1 head advancement passed;
  the second decision was not accepted. Repeat with shorter /tmp test paths
  that fit the notification so both decisions complete promptly.
- **N11 partial:** actual long-command clipping correctly routes through full
  review, preserving request identity; enlarged-font coverage still pending.
- Final result verified parent retained, both children absent, no retry or
  policy change. No permanent/session permission was granted.

Additional observation to investigate after pending live decisions: Samsung's
expanded Wing group showed two identical monitoring cards in captures at 12:17
and 12:22 (native foreground notice plus group summary records). Do not dismiss
this as transient without checking native rendering and lifecycle. It is not
resolved by the notification-action fix. Raw captures remain private.

### WING-FIFO-SHORT: complete live FIFO pass

- 12:30:57: exact test chat Working captured before Home.
- 12:31:46: **two approvals** in one notification, head child a. Hermes chose
  its safe scratch directory instead of /tmp; shorter child names fit in the
  expanded notification, so no additional review navigation was necessary.
- 12:33:11: actual native Once tap on a. The same notification ID advanced to
  **one approval for b**, while b remained pending independently.
- 12:34:29: actual native Deny tap on b. By 12:34:41, the same slot showed the
  final result: a approved and completed as a no-op on its verified absent path;
  b denied and did not run. No retry, persistent grant, or policy change.
- **N08 PASS on 2330 for the agreed two-request queue.** Original script's
  three-item sample was reduced to two for this live run; concurrency, exact
  head advancement and both accepted decisions are directly evidenced.
- Hermes again labelled its prose BLOCKED/FIFO not established. It cannot infer
  the Android observations from its tool result alone. Actual captured two-then-
  one counts, commands and successful outcomes are the evidence for this pass.
- Manual remains enabled for the continuing approved batch; restore Smart
  afterward. Both FIFO test parents were deliberately left intact.

User preference for subsequent test prompts: provide a copyable text block plus
separate clickable Sent confirmation, rather than putting the prompt only in a
question or blockquote.

### WING-LOCK-2330: privacy observed; post-unlock decision missed expiry

- 12:39:53: exact test chat Working before Home/screen sleep. Existing lock
  delay was respected; keyguard showing=true and inputRestricted=true by
  12:40:26. Secure/enabled lock verified; no security settings changed.
- Real approval delivered by 12:40:23. Locked Samsung shade exposes generic
  Wing text, with command and approval buttons hidden by phone privacy policy.
- 12:43:12: Wing entry tapped while keyguard remained showing=true and input
  restricted; the same approval remained pending. No approval choice was sent.
- Explicit NOW unlock cue and clickable Phone unlocked question sent; user
  confirmed normal unlock. Keyguard readback showed showing=false and
  inputRestricted=false. No decision was tapped after unlocking before expiry.
- By 12:46:49 the same notification showed the final result: approval timed
  out, script did not run, no retry or policy change. Operator delay prevented
  the post-unlock decision; this is neither an app failure nor a complete pass.
- The locked-entry tap did not establish that the action Activity launched:
  screen timeout and hidden controls limit that evidence. Repeat promptly with
  a new print-only request and complete the explicit decision after unlocking.
- This configuration cannot exercise a visible Once button while locked because
  Samsung hides its content/actions. Preserve that limit in the final evidence.

### WING-LOCK-RETRY: locked privacy and post-unlock Once accepted

- 12:54:50: exact test chat Working observed on the list; backgrounded and
  screen put to sleep. Existing secure keyguard became showing=true and
  inputRestricted=true. No security settings changed.
- By 12:55:44, real print-only approval existed. Actual locked screen showed
  generic Wing content without command or choices. User received an explicit
  NOW unlock cue, then confirmed normal unlock. Readback showed showing=false
  and inputRestricted=false; command and four choices were visible afterward.
- 12:57:46: explicit native Once tap on the verified WING-LOCK-RETRY command.
  By 12:57:54, the same notification ID held its successful execution result.
  Hermes's prose again said no approval was generated, contradicted by the
  actual pending request, captured controls, and accepted phone decision.
- Monitoring disappeared by 12:57:21 and remained absent before the tap. This
  is a successful real-phone approval after watcher shutdown. No pre-tap
  socket/netpolicy trace was captured, so do not claim APP_BACKGROUND blocking
  or a particular disconnected recovery branch was established by this run.
- **N13 partial:** privacy and normal-unlock/explicit-action flow passed.
  Direct action while locked followed by cancelled authentication remains
  unexercised because Samsung hides actions under the current privacy policy.
- Manual remains temporarily enabled for the continuing approval tests.

### WING-LARGE-ALWAYS: enlarged actions and cancellation passed

- 13:05:39: recorded original system font scale 1.0, temporarily set 2.0.
  Exact test chat Working observed before backgrounding. Actual print-only
  approval arrived by 13:06:15.
- In Samsung's light notification shade at 200% text, all four choices remained
  visible in two rows. The command clipped, so full-command review was required.
- 13:07:34: native Always tap opened the owning chat and its dark review dialog;
  correct command displayed. Cancel and Always allow remained reachable at
  enlarged size. Cancel tapped; fresh UI still showed the same pending approval.
- Then explicitly denied in chat. Final answer confirmed no execution, retry,
  policy change, or substitute operation. No permanent/session grant was made.
  Original font scale 1.0 restored after the check.
- **N19 controlled confirmation/cancellation PASS.** Permanent acceptance was
  deliberately not tested because the stock execute_code pattern is broad.
- **N11 enlarged-text light shade and dark dialog coverage passed.** Dark
  notification shade remains uninspected; preserve that visual coverage limit.
- Usability observation: at 200% text, the permanent-pattern warning follows
  a long backend description below the initially visible scroll area. The
  description itself says approval is one-shot, creating confusing wording
  alongside Always. The existing warning is present in the scrollable content
  in source; it was not scrolled into view in this capture. No scope change
  was inferred from the backend prose and no Always confirmation was accepted.

The user separately reported that the connection indicator can say unavailable
while chatting still works, and explicitly requested one subagent. Its focused
investigation and regression evidence are recorded in
[connection status investigation](2026-09-24-connection-status-investigation.md).

Post-batch cleanup: original font scale **1.0** restored. Claw/default approval
mode saved back to **Smart** and read back with no unsaved changes; timeout 300
and existing allowlist retained. No live test approval remains pending.

Connection-status follow-up: 2331 / 23312 (`d6cf733`) installed after full-suite
2,708 passes / 12 opt-in skips, clean analysis and release identity/signature
checks. Startup shows Connected; exact previous failed owner was not captured.
The native notification layout remains the tested 2330 implementation. Attempt
to finish dark-shade 200% inspection in the isolated emulator was interrupted
when that emulator disconnected; do not record a visual pass for that attempt.

### Final four: resumed testing, fixes deferred

User requested finishing N09/N14/N17/N18 before the next fix pass. On 2331,
temporarily re-enabled the previously authorized Manual mode on Claw/default,
read back with unchanged timeout 300 and allowlist. Restore Smart after this
batch. Font remains 1.0. N14 is first; phone Wi-Fi/mobile-data initial states
are both enabled. A detached-process probe completed successfully; a bounded
offline helper with independent restoration watchdog is staged but not run.
The helper will only tap coordinates verified against the actual pending test
notification. Real Hermes outcome and synthetic emulator evidence remain
separate. No new application fix has been made during this test phase.

N14 live attempt in progress: exact WING-N14-2331 approval first captured at
13:31:56. The physical shade showed its full print-only command and four
choices. Fresh UI exposed the Once action as `com.tarkilhk.wing:id/once` with
content description “Allow this request once”. The staged offline helper was
updated to require a fresh offline UI dump, exact test marker and exactly one
Once node before tapping; it aborts if these checks fail.

13:35:52: detached bounded outage helper launched with a 45-second independent
restoration watchdog. Wireless debugging subsequently stopped responding; the
old address did not reconnect and automatic restoration could not be verified.
User received an explicit NOW cue to check/re-enable Wi-Fi/mobile data and send
the current debugging address. Until private phone logs/captures are recovered,
do not infer that a button tap occurred, that restoration completed, or that an
application failure was reproduced. The late start also limits retry coverage
before the five-minute approval expiry. No automatic decision retry was staged.

Recovered outcome: user restored/confirmed Wi-Fi and mobile data enabled.
Wireless-debugging ports changed several times; stable reconnection ultimately
used port 37837. Recovered helper log contains only its starting timestamp;
no offline UI dump, tap marker, or screenshots exist. No test helper process
remained at the final connection check. Both network settings read back as 1.
**Offline action attempt is invalid/inconclusive, not a Wing failure.** Do not
repeat this wireless-debugging-dependent approach on the physical phone.

User confirmed on desktop that WING-N14-2331 timed out and did not run. A stale
approval was still posted at initial recovery; after reopening only Wing's list
and reconnecting, it disappeared. At 13:45, the active notification dump had no
test marker and the actual shade agreed. **Expired-request reconciliation
passed; no stale-action tap was available afterward.** Live offline and stale
target decision branches remain unverified; use isolated native QA separately.

### Isolated mixed-input and dark visual coverage

Existing isolated Android 16 QA app, fake Hermes only: posted an approval,
then one question, then a newer answer in the same synthetic chat. Actual
native notification retained the approval head and showed **1 approval ·
1 question**. Stored state retained the newer answer beneath both inputs.
Native Deny produced exactly one approval.respond for qa-1 and advanced the
same chat notice to **1 question**, with no premature answer replacement.
This covers the client sequence; it is not evidence that stock Hermes can
generate that same-chat combination on demand.

Actual expanded dark Android shade at font scale 2.0 showed readable command,
both counts and all four choices in two rows. This closes the dark visual
coverage gap with emulator evidence, alongside the earlier physical Samsung
light-shade check. No production UI changes were made. The warning-below-fold
and contradictory backend-description observations remain for the fix pass.

### N18 first attempt: operator missed expiry

WING-N18-2331-A appeared in the new disposable chat at 13:55:58.
The operator reached Session only after the five-minute expiry, around 14:02.
The notification disappeared after that tap. Reading the actual chat confirmed
A timed out without a decision, B was not called, and no second approval was
applicable. This is an invalid Session test due to operator delay, not a Wing
Session failure or pass. The user will operate the phone action on the retry.

### N18 retry: PASS on 2331

User sent WING-N18-RETRY in the same new disposable desktop chat and personally
tapped Session on the phone notification within the pending window. At 14:07,
the observed same-slot result (ID 931318455) reported A executed successfully,
B executed successfully, and no additional approval for B because the Session
grant applied. The chat list showed that test idle. This establishes the live
Session flow; it does not imply a print-only permission pattern.

Final cleanup: Claw/default saved back to **Smart** and read back as smart,
timeout **300**, unchanged allowlist, and **No unsaved changes**. No permanent
grant was accepted. Session permission belongs to the disposable test chat.

Ledger after this batch: **14 passed, 4 partial, 0 failed, 1 blocked**. The four
partial cases are mixed input (synthetic coverage only), dismissal concurrency,
locked-action authentication (hidden by phone privacy), and offline/stale
actions (live outage attempt invalid). Secure input remains blocked. These
counts describe scenario coverage; they do not dismiss the separately recorded
duplicate Watching cards, generic recovery text, or Always-warning usability
observations awaiting investigation. No new production fixes in this batch.

User clarified the lock-screen acceptance criterion: no actions while locked is expected. N13 is PASS; the artificial hidden-button/cancel-authentication branch is removed. Current ledger: 15 passed, 3 partial, 1 blocked. User requested mixed-priority, dismissal/new-request, and manually operated offline retests.

### Dismissal retest: PASS for stock sequential requests

User dismissed WING-DISMISS-A on the physical phone, then answered Summary on desktop after the NOW cue. User confirmed a new WING-DISMISS-B notification appeared. Dismissal does not suppress the next distinct request. This is sequential replacement, not a simultaneous-request race. N10 passes with earlier dismissal retention across reconnect/restart. Ledger: 16 passed, 2 partial, 1 blocked.

Manual offline retest preparation: temporarily saved Claw/default Manual again, read back timeout 300 and existing allowlist unchanged. Smart restoration is pending this test. User will exclusively operate the offline action and reconnection; no remote outage helper will run. Use a fresh chat to avoid the previous execute_code Session grant.

### User-operated offline retest: retained request and successful retry; review UX issue

User generated WING-OFFLINE-RETEST in a fresh chat, disabled both phone network
transports, and tapped native Once. Wing opened the chat and Review command
dialog. Confirming Allow once returned to an Approval needed card with disabled
buttons. After restoring connectivity, desktop still showed the approval pending
and the phone notification remained. A fresh notification Once tap reopened the
review dialog; confirming then successfully approved the operation. Thus this
review-routed offline attempt did not silently approve or automatically retry;
request retention and explicit online retry passed by user observation. This is
not a trace of the short-command direct-action route while offline.

User screenshots show Reconnecting and enabled dialog confirmation above a
disabled chat approval card. They also show an Executed successfully response
already visible above the pending card; the origin/turn of that response is
unverified and must not be interpreted as proof of execution while offline.

Source verification: native ChatNotifications.kt routes choices to review when
its estimated command layout exceeds three lines (one at enlarged text);
main.dart also requires review for Always or an unloaded chat. The review path
opens the chat before displaying its dialog; confirming closes the dialog and
attempts the decision, leaving the same underlying approval card on failure.
Exact triggering branch for this phone request is not traced. Dialog confirmation
is not disabled for disconnected state. UX finding: duplicate review surfaces
and poor explanation of why offline confirmation cannot complete. No production
code changed. Wireless debugging is disconnected after the test; restoring Smart
remains pending access or a manual user change.

Post-offline cleanup verified at 14:34: reconnected at the user-provided wireless
debugging address, saved Claw/default back to Smart, and read back smart, timeout
300, unchanged allowlist and No unsaved changes. The prior screenshot's apparent
execution contradiction is resolved by the current chat view: a 14:26 completed
turn precedes the repeated user prompt at 14:27 and its successful 14:28 reply.
The earlier success text is not evidence of execution during the tested outage.

Mixed-priority regression rerun: flutter test --no-pub
test/chat_notification_coordinator_test.dart --plain-name input: **3 passed**.
Verified input retains priority over a newer answer and exposes the answer after
resolution; mixed inputs retain first-seen FIFO and question counts; reading a
hidden answer does not resolve pending input. These are coordinator tests, not
a completed end-to-end emulator question-to-answer sequence. The latter remains
unproven: reopening the existing native fixture showed the answer without a
question form. Do not upgrade N09 to a full native/live pass from these tests.
