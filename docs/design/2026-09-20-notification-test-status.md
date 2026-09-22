# Notification test status

Updated **22 September 2026** after fixes and deployment. Phone: Galaxy S23 Ultra,
Android 16; Wing **2327** (Android version code 23272). The five live runs below
were performed on build 2326; their two gaps are fixed in code and await live retest.

Evidence: [20 September live results](2026-09-20-notification-live-results.md),
[22 September retest results](2026-09-22-notification-retest-results.md).
Instructions: [two focused follow-up retests](2026-09-22-notification-followup-retests.md)
and [original test script](2026-09-20-notification-live-test-prompt.md).
Fix evidence: [build 2327 fixes](2026-09-22-notification-followup-fixes.md).

## Current summary

- Today's **five runs are finished: 3 passed, 1 partially passed, 1 failed**.
- Both newly identified gaps are fixed, automatically tested and installed in
  build 2327. **Two focused live retests remain** before changing those outcomes.
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
| Initial generic input notice | Fixed in build 2327: first unopened-chat transition loads the current structured request without history/navigation. Regression tests pass; exact live case A pending. |
| Unread reply after force-stop/relaunch | Fixed in build 2327: silent same-slot restoration after relaunch, respecting read/dismissal/ownership/preferences. Actual Android emulator regression passes; exact live case B pending. |
| New activity versus full-bottom reading | Older history correctly retained the notice. New activity showed the answer but did not clear; a full-bottom scroll did. Accepted bottom rule passes; shortcut behavior warrants UX follow-up. |

The original idle-reconnect watcher/replacement defect was fixed in `120868e`
(build 2325); LIVE-5/6 verified it. Build 2326 fixes were committed in `f291f59`.
Today's two observed gaps are fixed in build 2327, but are not counted as live
passes until their focused retests complete.

## Original scenario checklist

| # | Scenario | Status |
| --- | --- | --- |
| 01 | Reply and reading | Passed: tap/latest-answer clearing plus older-history retention/full-bottom clearing; shortcut detail above |
| 02 | Replacement and identical replies | Passed: exact identical text produced a fresh same-slot update |
| 03 | Foreground behavior | Passed: normal reply suppressed; real input notification allowed |
| 04 | Monitoring and interruption | Passed: live summary, lock-screen delivery, real desktop Stop and watcher shutdown |
| 05 | Three-question batch | Partial on 2326: initial notice generic. Fix installed in 2327; case A pending. Counts, advancement, Review, earlier completion/privacy covered |
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
| 16 | Restart / reconnect | Failed explicit force-stop unread-reply restoration on 2326. Fix installed in 2327; case B pending. Dismissal, idle reconnect and ordinary retention covered |
| 17 | Secure input | Blocked: no harmless generic dummy-data flow exposed by runtime |
| 18 | Session permission | Blocked: no real safe approval request |
| 19 | Always permission | Blocked: no real safe approval request; no permanent grant attempted |

Multi-chat/profile isolation and counts cannot be proved by these one-chat runs.

## Build 2327 validation and installation

- **95 focused tests** pass, including cold structured input, same-revision silent
  restoration, queued swipe dismissals, current ownership/preferences, and delayed
  live-event/navigation races. Full Flutter suite: **2,687 passed, 12 skipped**.
  Code analysis clean; all **28 release-tooling tests** and source version check pass.
- Actual Android 16 emulator: same-ID/text reply restored silently after force-stop;
  real swipe dismissal stays absent on relaunch; counts 3/2/1 and privacy pass.
- Signed production ARM64 build verified against the pinned certificate, package,
  non-debuggable flag and version. Installed with data-preserving `adb install -r`;
  phone package readback confirms **1.0.1 / 23272** on 22 September.
- APK SHA-256: `be514fc658fa1f9dbf4db2f33979d1dcc687402b46ebe9f534ad6e5f41074968`.
- Latest stock Hermes source inspected at
  `e2f8a0731bf26e95b31e35d73e71e183a1045b81`; no backend changes or new polling.
- Temporary emulator stopped. No live Hermes request was started during fixes.

## Earlier build 2326 fixes and automated evidence

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

1. Run the **two focused live retests** on installed build 2327 in the current
   conversation: initial structured-input content before opening the chat, then
   unread reply restoration/read clearing after force-stop. Keep New activity's
   extra-scroll behavior as a separate UX follow-up.
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
