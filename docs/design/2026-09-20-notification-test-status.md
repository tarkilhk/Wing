# Notification test status

Updated **22 September 2026**. Phone: Galaxy S23 Ultra, Android 16; Wing **2326**
(Android version code 23262). No source changes were made during today's tests.

Evidence: [20 September live results](2026-09-20-notification-live-results.md),
[22 September retest results](2026-09-22-notification-retest-results.md).
Instructions: [test script](2026-09-20-notification-live-test-prompt.md).

## Current summary

- Today's **five runs are finished: 3 passed, 1 partially passed, 1 failed**.
- Original **19-scenario ledger: 5 passed, 3 partial, 1 failed, 10 blocked**.
  A passed row covers its runnable checks; separately documented blocked branches
  are not silently treated as passed.
- Sound is **confirmed working by the user**. No dedicated repeat is needed.
- Capture stopped; previews restored to enabled; Android attention category
  remains enabled; phone left on Home. No backend policy, credentials or phone
  authentication changes. No test request remains pending.

## Fixes and remaining issues

| Item | Current evidence / disposition |
| --- | --- |
| Missing remaining-question count | Build 2326 renders 3 → 2 → 1 correctly in collapsed/expanded notifications once the request is loaded; hidden previews retain count and hide content. Live-verified today. |
| Stale Needs input after desktop resolution | Actual desktop Summary submission after dismissal/force-stop/relaunch cleared the untouched list to Idle. Continued-work variant resumed monitoring, delivered exact reply and stopped. Live-verified today. |
| Initial generic input notice | First background notice said only Open the chat to continue until chat opening loaded the real batch. Still a content/coverage gap. |
| Unread reply after force-stop/relaunch | Failed restoration: notice disappeared and did not return after reconnect, without reading or dismissal. Separate from ordinary backgrounding. |
| New activity versus full-bottom reading | Older history correctly retained the notice. New activity showed the answer but did not clear; a full-bottom scroll did. Accepted bottom rule passes; shortcut behavior warrants UX follow-up. |

The original idle-reconnect watcher/replacement defect was fixed in `120868e`
(build 2325); LIVE-5/6 verified it. Build 2326 fixes were committed in `f291f59`.
Today's observed gaps are not silently counted as fixed.

## Original scenario checklist

| # | Scenario | Status |
| --- | --- | --- |
| 01 | Reply and reading | Passed: tap/latest-answer clearing plus older-history retention/full-bottom clearing; shortcut detail above |
| 02 | Replacement and identical replies | Passed: exact identical text produced a fresh same-slot update |
| 03 | Foreground behavior | Passed: normal reply suppressed; real input notification allowed |
| 04 | Monitoring and interruption | Passed: live summary, lock-screen delivery, real desktop Stop and watcher shutdown |
| 05 | Three-question batch | Partial: counts, advancement, Review, earlier completion and privacy covered; first background notification still generic until opening |
| 06 | Once | Blocked: Smart auto-approved the safe operation |
| 07 | Deny | Blocked: no real safe approval request |
| 08 | FIFO approvals | Blocked: no real safe approval requests; concurrency unverified |
| 09 | Mixed input priority | Blocked: no real safe approval request; concurrency unverified |
| 10 | Swipe dismissal | Partial: preserved across reconnect and force-stop/relaunch; concurrent new-request branch uncovered |
| 11 | Long command / large-text approval layout | Blocked: no real safe approval request |
| 12 | Hidden previews / channels | Passed for questions/counts and category diagnostics; approval privacy branch blocked |
| 13 | Unlocking approval actions | Blocked: no real safe approval request |
| 14 | Offline / stale approval actions | Blocked: no real safe approval request |
| 15 | Desktop resolution | Partial: actual desktop answer/reconnect and continued-work cleanup pass; already-running watcher polling branch untested |
| 16 | Restart / reconnect | Failed explicit force-stop unread-reply restoration; pending dismissal, idle reconnect and ordinary unread retention covered |
| 17 | Secure input | Blocked: no harmless generic dummy-data flow exposed by runtime |
| 18 | Session permission | Blocked: no real safe approval request |
| 19 | Always permission | Blocked: no real safe approval request; no permanent grant attempted |

Multi-chat/profile isolation and counts cannot be proved by these one-chat runs.

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
  version code 23262 and version name 1.0.1. Installation was on 20 September;
  the subsequent live retest evidence is recorded above for 22 September.
- APK: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`; SHA-256
  `723f63df15c54e59699a560e4749b1b1b57af2130f969846578682bb6f64c085`.

These are automated/client-fixture results. They do not upgrade the live scenario
statuses above or establish stock approval capability. Sound confirmation above
comes from the user, independently of automated checks.

## Next work

1. Investigate/fix initial structured-input content for unopened chats and unread
   reply restoration on relaunch after force-stop; review New activity's read
   acknowledgment behavior. Retest those specific gaps afterward.
2. Keep actual approval tests blocked until a genuine harmless request can be
   produced under the deployed policy. No policy changes or riskier probes are
   authorized merely to make the test produce an approval. Run scope-granting
   cases last; permanent acceptance still requires explicit instruction and a
   verified narrow scope.
3. Cover safely supported concurrent-input and watcher-already-running branches.
4. Ask Hermes to clean up the remaining disposable test parent when requested:
   `/home/tarkil/.hermes/cache/scratch/wing-notification-test-CZeiJPit`.

Raw captures remain private under `/tmp/wing-live-notification-test/` and
`/tmp/wing-notification-retest-2026-09-22/`; neither is committed.
