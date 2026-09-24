# Monitoring outage investigation — Wing 2332

Status: root cause reproduced; client correction implemented for build 2333.
Release validation complete; signed 2333 installed on the phone. The combined
outage recovery live retest remains pending.

## Finding

Wing forgets its notification transition history on a socket disconnection or a
failed activity read. It retains the separate set that keeps monitoring alive,
but cannot correlate that remembered work with its completed result afterward.
The next successful idle snapshot drops the monitoring set without fetching or
posting that result.

This is an existing controller bug, not evidence that Android killed the app or
that the foreground service necessarily stopped while the phone was offline.
The lost-history reset predates 2332 (introduced in commit 28a36422); 2332 improved
the recovered result text only on paths that actually reach result recovery.

## Physical evidence and limits

The combined phone test recorded one app-owned monitoring notice, ID 214601,
with two working chats before the network outage. After reconnection the process
was still alive, the service was absent, and the target answer notification was
absent. Reopening only Chats did not restore the answer notification.

The captured logs do not cover the relevant stop event. The two monitored chats
were not individually identified. Therefore these artifacts cannot establish
that the target chat was tracked, or the precise moment the watcher stopped.
The controller reproduction below demonstrates a sufficient cause consistent
with the observed after-reconnection state; it does not fill these evidence gaps.

Private evidence remains under `/tmp/wing-notification-fixes/` in the
`recovery2332-before-*`, `recovery2332-after-*`, and
`recovery2332-reopened-notifications.txt` captures. No device access or settings
changes were performed by this investigation.

## Reproduction

Isolated regression file: `test/notification_outage_recovery_test.dart`.
Run from the repository with the project toolchain loaded:

```sh
flutter test --no-pub test/notification_outage_recovery_test.dart --reporter expanded
```

Result: **1 passed, 3 failed**, consistently, in seconds. Output saved privately
as `/tmp/wing-notification-fixes/outage-controller-repro.txt`.

All four variants establish a verified unopened desktop chat as working. They
provide the same exact structured assistant history row and then the same idle
runtime/session snapshot:

| Variant | Monitoring during uncertainty | Result after idle snapshot |
| --- | --- | --- |
| No interruption | Active | Exact answer delivered; monitoring stops (pass) |
| `networkUnavailable()`, then healthy activity event | Remains active | No answer; monitoring stops (fail) |
| Failed activity read, then healthy activity event | Remains active | No answer; monitoring stops (fail) |
| `networkUnavailable()`, then actual `resumeConnection(networkChanged: true)` | Remains active | No answer; monitoring stops (fail) |

The assertions confirm monitoring is retained at disconnection and is off after
the idle reconciliation. The failing assertion is specifically the absent exact
answer notification. The test does not infer failure from generic exceptions or
phone screenshots. It exercises the actual public network-recovery entry points
and real notification reconciliation, with only gateway transport/storage
responses supplied by the existing test host.

These results describe the pre-fix reproduction. The retained regression file
now includes further safeguards and is green after the correction below.

## Code path

In `lib/core/services/profile_workspace_controller.dart`:

1. The resource socket callback sets `_notificationSnapshot = null` at line 980.
   It does not clear `_backgroundChats`, so `hasActiveChats` remains true.
2. `_reconcileNotificationActivity` considers an idle unloaded runtime relevant
   only if `_notificationSnapshot` already tracks that runtime/session identity
   (lines 6057–6066).
3. The first healthy snapshot following the outage therefore omits that idle
   runtime from the candidate results. The replacement `_backgroundChats` map
   (line 6149) is empty once the previously working runtimes are idle.
4. `previous == null` returns before any completion notification is produced.
5. Registry activity becomes false. `BackgroundMonitoringService._sync()` sends
   the native stop operation when `hasActiveChats()` is false. Opening Chats
   again cannot reconstruct the discarded completion transition.
6. A failed discovery/activity/ownership read causes the same history reset in
   the broad catch at line 6204, even when work was verified earlier.

A separate display gap is visible in
`lib/core/services/profile_workspace_notifications.dart`: loaded reconnecting
chats count as `reconnecting`, but every unloaded `_backgroundChats` entry is
always counted as `working`. Even while monitoring survives a lost connection,
the status can continue to claim work is running rather than say reconnecting.

## Baseline purpose and safe fix direction

A fresh connection has no evidence that an old idle answer is a new completion.
The initial snapshot must remain a baseline; startup must not create notices for
every historical idle chat. Existing tests also correctly reject completion from
missing/unknown runtime state, ambiguous ownership, or failed reads.

That rule was applied too broadly to previously verified unfinished work. A
transport interruption changes confidence in the current state, not the fact
that Wing was watching an identified unfinished turn.

Proposed client-only correction:

- Separate initial/untrusted discovery from retained, verified unfinished work.
  Preserve the exact connection, profile, stored-session, and runtime identity
  across socket loss and transient snapshot failures at both reset sites.
- On recovery, reconcile retained work against a fresh successful stock snapshot.
  For a matching confirmed idle runtime, fetch the existing official history
  page and use the current structured answer projection/result identity. Do not
  parse model prose or invent a result based solely on disappearance.
- Keep monitoring through uncertainty and through result reconciliation/posting.
  Retire retained work only after a confirmed terminal or waiting state has been
  handled. A missing/unknown runtime requires an explicit recovery decision;
  it must not silently count as completed.
- Preserve the initial baseline and ownership protections for chats that were
  never reliably tracked. A new runtime identity after reconnect must not be
  treated as proof that an old tracked runtime finished.
- Describe retained unloaded work as reconnecting while its owner is recovering,
  so the same single monitoring card reflects the actual uncertainty.

Do not just delete both resets without checking the initial-baseline, identity,
ownership, waiting-input, duplicate-notification, and history-failure branches.
No new backend endpoint or modified Hermes deployment is proposed.

## Desktop reading is not the cause

The accepted spec clears reply notifications only on reaching the answer in Wing.
The stock desktop read flag is chat-wide and does not establish that the latest
answer was reached. See the design interview Q14 and scenario 15 in
`2026-09-20-notification-live-test-prompt.md`.

The failing controller path does not read a desktop unread/read flag at all. The
watcher-driven `reconcileNotificationRequests` polls pending input resolution,
not remote reply-read state. Merely seeing this answer on desktop cannot explain
or excuse its missing Wing notification under the agreed behavior.

## Follow-up validation

After implementation, make all four reproduction variants pass; retain coverage
for cold baseline, missing/unknown runtime, exact ownership, and loaded-chat
recovery. Add summary coverage showing an unopened tracked chat as reconnecting.
For the phone retest, first positively identify the test chat among tracked work;
then capture the monitor through manual network loss, completion while offline,
and reconnection. Confirm exact recovered reply text, single notice, monitoring
shutdown only after reconciliation, and clearing when the answer is reached.

## Implemented correction and verification

The verified unfinished-session snapshot now survives both disconnects and
failed discovery/activity/ownership reads. Reconciliation preserves identities
through missing/unknown rows and conflicting owners. A confirmed idle result
stays monitored through its history read and asynchronous notification posting;
a failed history read retains the pending result for the next existing recovery
or activity observation. Initial idle snapshots still create no notification.
An explicit uncertain-runtime set drives the existing Reconnecting summary.
No additional polling or backend modification was introduced.

Current upstream verified at `8def746896dce8532db288c600dbf696095243ee` on
24 September. Read-only inspected stock `tui_gateway/methods_session.py`
(`session.active_list` includes non-finalized idle runtime rows),
`tui_gateway/contracts/sessions.py`, and `hermes_cli/web_routers/sessions.py`.
The correction uses the same active-list, profile ownership and history calls.

Parent independently reran the original reproduction before modifying code:
1 passed / 3 failed, all failures due to absent recovered reply. After fixing,
11 outage-recovery tests and 24 existing notification-coverage tests pass. New
checks include missing/unknown runtime, changed runtime, ambiguous ownership,
history failure followed by recovery, delayed history and notification delivery,
no duplicate alerts, message identity, and silent cold idle baseline. Existing
loaded-chat, pending-input, ownership and foreground rules remain covered.

This establishes a reproducible code-level cause and correction. The phone logs
still do not prove the exact instant its service stopped. The next live test must
confirm the corrected full device behavior; automated results are not a live pass.

Final regression validation: complete suite ran **2,727 passed / 12 intentional
skips / 1 outdated expectation failed**. That test had explicitly treated a
missing side-task runtime as completed. It now requires monitoring to remain
active until a corroborated waiting state with no side tasks; all **41 tests**
in the final monitoring/outage/notification coverage run passed. No production
logic changed after the complete suite; the only later source edit was braces.
Release tooling: **28 passed**. Private logs: outage-full-suite.txt,
outage-final-focused.txt, and outage-release-tooling.txt under the evidence dir.

## Release artifact

- Build 2333, Android versionCode 23332, versionName 1.0.1.
- Signed release ARM64 APK; non-debuggable and pinned certificate verified.
- SHA-256: `dc05f94dfbcc215201ca15ac7f8c8c27e18e0d3227da8a52100d7b9d07b5c003`.
- Final static analysis: clean; release version/whitespace checks pass.
- Phone deployment confirmed at 19:26:42 Singapore on 24 September: data-
  preserving installation succeeded; package versionCode read back as 23332 and
  versionName 1.0.1. Launch started process 32579 behind the locked system UI;
  chat connectivity was not visually verified while locked. Source `bc1ce59`.
- Retest only the combined outage recovery: known test chat working, phone
  backgrounded, user disconnects phone networking, desktop finishes, reconnect,
  exact latest reply notified once, watcher settles, reading that answer clears
  its notification. Prior offline approval and scope-layout checks passed.
