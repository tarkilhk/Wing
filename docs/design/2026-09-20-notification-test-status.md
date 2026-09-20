# Notification test status

Updated 20 September 2026 after live testing on a Galaxy S23 Ultra, Android 16.
Phone build: **2326 installed and verified** (Android version code 23262).
Live evidence below comes from build 2325; both fixes await tomorrow’s live retest.
Detailed evidence: [live results](2026-09-20-notification-live-results.md).
Test instructions: [19-scenario script](2026-09-20-notification-live-test-prompt.md).

## Summary

- **19 scenarios accounted for:** 4 passed, 5 partially covered or with an issue,
  10 blocked by the current safe test conditions.
- Both confirmed issues are fixed in the client; no further user-driven phone tests
  tonight. Remaining live checks resume tomorrow.
- Test capture is stopped. Message previews and Android's attention category
  were restored to their original enabled settings. Backend policy and phone
  authentication settings were not changed.

## Confirmed issues

| Issue | Evidence | Fix status |
| --- | --- | --- |
| Missing unanswered-question count | N05: a real three-question batch advanced correctly, but the notification never showed its remaining count | Fixed: count in collapsed and expanded notification text; Android emulator regression passes |
| Stale Needs input chat-list status after desktop resolution | N10: after dismissal and process restart, desktop finished; list still said Needs input after reconnect; opening chat showed the completed answer | Fixed: refresh resolved requests and reconcile the cached activity snapshot; regression tests pass |

The original watcher/replacement bug is already fixed in main commit `120868e`
and build 2325. LIVE-5/6 verified that fix on the phone.

## Scenario checklist

| # | Scenario | Status |
| --- | --- | --- |
| 01 | Reply and reading | Partial: tap/latest-answer clearing passed; older-history case tomorrow |
| 02 | Replacement and identical replies | Passed: exact identical text still produced a fresh same-slot update |
| 03 | Foreground behavior | Passed: normal reply suppressed; real input notification allowed |
| 04 | Monitoring and interruption | Passed: live summary, lock-screen delivery, real desktop Stop and watcher shutdown |
| 05 | Three-question batch | Partial: Review, advancement and completion passed; original count display failed; fix awaits phone retest |
| 06 | Once | Blocked: Smart auto-approved the safe operation |
| 07 | Deny | Blocked: no real safe approval request |
| 08 | FIFO approvals | Blocked: no real safe approval requests; concurrency unverified |
| 09 | Mixed input priority | Blocked: no real safe approval request; concurrency unverified |
| 10 | Swipe dismissal | Partial: retained across reconnect and process restart; new-request branch not covered |
| 11 | Long command / large-text approval layout | Blocked: no real safe approval request |
| 12 | Hidden previews / channels | Passed for questions and category diagnostics; approval privacy branch blocked |
| 13 | Unlocking approval actions | Blocked: no real safe approval request |
| 14 | Offline / stale approval actions | Blocked: no real safe approval request |
| 15 | Desktop resolution | Partial: N15 reconnect cleanup passed; N10 fix awaits phone retest; watcher-active branch untested |
| 16 | Restart / reconnect | Partial: idle reconnect, unread retention and dismissed pending-question restart passed |
| 17 | Secure input | Blocked: exposed masked flows affect credentials/accounts; no harmless dummy flow reported |
| 18 | Session permission | Blocked: no real safe approval request |
| 19 | Always permission | Blocked: no real safe approval request; no permanent grant attempted |

Audible sound is **confirmed working as expected by the user**, during the
follow-up fix session. Multi-chat/profile isolation and counts cannot be proved
by this one-chat run.

## Fixes and automated evidence

- **Question counts:** Dart already supplied the remaining-input count, but the
  native standard notification template ignored it. Both collapsed and expanded
  text now include it. The existing custom approval layout retains its count row.
- **Desktop resolution:** the global activity reconciliation previously skipped
  loaded chats waiting for input, and did not update the list's separately cached
  activity rows. A non-waiting snapshot now triggers the stock lightweight resume
  read to reconcile requests, and known cached rows follow the validated snapshot.
  Newer live requests win over delayed reads; failed/unknown reads preserve pending
  state; running side tasks remain visible. No polling loop or watcher-lifetime
  extension was added.
- Stock Hermes source inspected at upstream main
  `c1488ac947c9bc33fd65ec464548dc9d8edd6122`: `session.resume` with
  `omit_messages` reports current running/open-request state without fetching
  history; empty `open_requests` may be omitted. No backend changes were made.
- Before fixing, controller regressions reproduced both the lingering question
  and stale activity row. The native rendering script failed on missing
  `3 questions`. After fixing, all 36 focused regressions pass, and
  `scripts/test_native_notification_counts.py --serial emulator-5554` verifies
  counts 3/2/1 in both Android layouts plus hidden-preview privacy.
- Visual inspection: actual Android 16 emulator notifications in light and dark
  mode, normal and 200% font sizes; count, question and Review remain readable.
- Static analysis passes; the complete Flutter suite passes **2,670 tests**, with
  12 skipped; all 28 release-tooling tests pass. Source version check passes for
  build 2326. Signed ARM64 APK verification passes: production package, version
  code 23262, non-debuggable, expected pinned release certificate.
- Installed with data-preserving `adb install -r`; package readback confirms
  version code 23262 and version name 1.0.1. No live scenario was run after install.
- APK: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`; SHA-256
  `723f63df15c54e59699a560e4749b1b1b57af2130f969846578682bb6f64c085`.

These are automated/client-fixture results. They do not upgrade the live scenario
statuses above or establish stock approval capability. Sound confirmation above
comes from the user, independently of automated checks.

## Resume tomorrow

1. Run the script’s [required build 2326 retests](2026-09-20-notification-live-test-prompt.md#build-2326-bug-fix-retests--run-first-next-session)
   first. A three-question batch must show
   3/2/1 remaining; after desktop resolution, the chat list must lose Needs input
   without opening Settings. Include the dismissed-question/restart sequence and
   the variant where desktop resolution leads to continued work and monitoring.
2. Finish older-history/latest-answer clearing and remaining restart branches.
3. Decide how to obtain a genuine harmless approval under the deployed policy.
   Do not change approval policy or escalate command risk without a separate
   decision. Run scope-granting cases last; permanent acceptance still needs
   explicit instruction and a verified narrow scope.
4. Cover supported concurrency/watcher-active branches; retain explicit blocked
   or unobserved labels for conditions the runtime cannot generate safely.
5. Ask Hermes to clean up its remaining disposable test parent when requested:
   `/home/tarkil/.hermes/cache/scratch/wing-notification-test-CZeiJPit`.

Private phone captures and raw observations remain under
`/tmp/wing-live-notification-test/`; they are not committed.
