# Build 2328 live retest results

Both focused cases finished on 22 September 2026, Galaxy S23 Ultra / Android 16,
Wing 1.0.1 build 2328 (Android version code 23282). User drove the existing Hermes
desktop test chat; Codex operated the physical phone. **A failed; B passed.**

## A — First input before opening: FAIL

- Fresh Wing process, connected Claw chat list; test chat remained unopened.
- 23:11:23 SGT: Watching 1 chat / 1 working observed; phone automatically sent Home.
- 23:12:04: monitoring stopped; zero Wing notification records. A second complete
  native notification dump confirmed zero records before opening the chat.
- User confirmed the actual three-question batch was pending on desktop.
- Returning to Wing's connected list showed the test chat as Idle. Opening it
  revealed Environment, Your input 1 of 3, with Preview/Production.
- Submitted Preview, Blue, Summary on the phone. After advancing, native notices
  correctly showed 2 questions / Color and 1 question / Output. This does not
  establish successful first delivery or 3-question notification rendering.
- 23:15:04: monitoring stopped after completion. Actual final reply was
  `WING-COLD-INPUT-2328 selected values: Preview · Blue · Summary.`
- No request remains pending. The initial delivery failure is still unresolved.
  Build 2328's stock-empty-approval regression proves a client race exists, but
  fixing that race did not fix the full real Hermes/phone path. It must not be
  described as the proven complete root cause of this live failure. More direct
  runtime evidence is needed before another first-delivery fix or confidence claim.

## B — Restore, tap, read, restart: PASS

- Returned to the ordinary connected chat list; monitoring observed and phone
  automatically backgrounded for the new 30-second desktop task.
- 23:16:24: exact fresh reply arrived:
  `WING-RESTORE-2328: The unread result is ready. Open Wing to read it.`
  Native chat notification ID was 1495764829.
- Force-stop removed it. At 23:16:27 relaunch restored the same ID/title/text with
  `ONLY_ALERT_ONCE|SILENT`. The underlying screen was the normal connected chat
  list; monitoring was stopped and opening the list had not cleared the reply.
- Tapped the actual reply in Android's shade. The owning chat showed the entire
  latest answer at the bottom. At 23:17:06 the native notification disappeared.
- Force-stopped and relaunched again: ten consecutive checks found no chat
  notification. Wing reconnected on the normal list. The read result stayed absent.
- This verifies the restored-reply read-clearing fix on the physical phone with
  an actual Hermes reply, including no resurrection after another cold launch.

## End state and next work

Capture stopped; phone returned Home. No pending test request, backend changes,
policy changes, privacy/channel changes or authentication changes. Sound was
already confirmed by the user and was not retested here.

Both planned retests are complete: **1 passed, 1 failed, 0 pending from this run**.
First unopened-chat input delivery requires further diagnosis and a fresh live
retest after a verified fix. Do not ask the user to repeat it unchanged.

Private evidence: `/tmp/wing-notification-2328-live/` contains timestamped native
observations, fresh UI snapshots, before/after restoration records and the
read/restart assertion. Raw captures are not committed.
