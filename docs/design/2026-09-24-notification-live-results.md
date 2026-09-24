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
