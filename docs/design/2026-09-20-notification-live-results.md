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
