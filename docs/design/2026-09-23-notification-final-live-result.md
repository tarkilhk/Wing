# Final saved-chat notification retest — PASS

23 September 2026, Galaxy S23 Ultra / Android 16. Installed Wing **2329**,
version **1.0.1 / 23292**, verified before the run. User operated the existing
Hermes desktop test chat; Codex operated the physical phone.

## Exact starting state

Opened the test chat once and confirmed the previous WING-TRACE-INPUT request
had timed out with all three questions unanswered. Its completed backend reply
explicitly said no values were inferred. No request remained pending.

Returned to the connected Claw chat list, force-stopped and relaunched Wing.
Confirmed it reconnected on the list. The target chat had a saved reading copy
and was not opened again before the tested notification arrived. This is the
persisted-state condition missing from the earlier fixtures.

## Actual observed sequence (Singapore time)

1. User sent WING-CACHED-2329 in the same desktop chat: a 30-second tool sleep,
   then one genuine structured batch for environment, color and output.
2. **00:07:36:** Watching 1 chat / 1 working observed; phone automatically sent
   Home while Hermes was working.
3. **00:08:15:** one fresh attention notification arrived, before opening the chat:
   `3 questions · Environment Preview (Recommended) · Production`.
   Expanded text contained the same count and useful choices. Monitoring stopped.
4. Visually inspected the collapsed notification, expanded it, and tapped the
   actual **Review** button. It opened the correct chat and Your input 1 of 3.
5. Selected Preview on the phone. **00:10:57:** the same native notification ID
   showed `2 questions · Color Blue (Recommended) · Green`.
6. Selected Blue. **00:11:15:** the same ID showed
   `1 question · Output Summary (Recommended) · Checklist`.
7. Submitted Summary. The input notice cleared, monitoring briefly resumed for
   Hermes' continuation, and the visible final reply confirmed:
   `WING-CACHED-2329 selected values: Preview · Blue · Summary.`
8. **00:11:35:** monitoring stopped; no test-chat notification remained. The form
   was gone, the final answer was visible, and the composer was ready to Send.

Native chat notification ID remained **1495764829** throughout the batch.
An assertion over the recorded trace verifies one slot, count sequence 3→2→1,
accepted final answers, no remaining input notification and monitoring stopped.
Android UI-tree capture twice failed to obtain an idle screen; visual inspection
and a fresh successful capture were used. This was a capture limitation, not an
application failure. No device settings were changed to work around it.

## Result and end state

**Case A passes on the actual phone with the fixed saved-cache path.** Case B
(restored reply → tap/read clear → another restart stays clear) already passed
on build 2328. Both bug-fix follow-ups are now live-verified; **zero focused
retests remain**.

This does not convert unsupported approval/secure-input scenarios or uncovered
concurrent-input branches into passes. The original ledger is **7 passed,
2 partial, 0 failed, 10 blocked**; see the canonical status.

Capture stopped; phone returned Home; no test request remains pending. Sound was
already confirmed by the user. No backend, approval-policy, authentication,
notification-channel, preview or battery-setting changes were made by Codex.

Private evidence is in `/tmp/wing-notification-2329-live/`: timestamped native
observations, fresh UI snapshots, screenshot and `verdict.json`. Raw phone
captures include unrelated notifications and are not committed.
