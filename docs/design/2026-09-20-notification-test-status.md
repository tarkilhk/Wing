# Notification test status

Updated **22 September 2026** after a traced investigation of the repeated first
question failure. The physical phone confirmed a saved-chat guard preventing the
request read. The correction is installed as **2329** (Android version code **23292**), with before/after Android
verification and guarded-cache regressions. [Investigation and evidence](2026-09-22-notification-cached-chat-investigation.md).

The completed 2328 live retests remain **A failed; B passed**. Only A needs a fresh
fixed-phone live run; the investigation is now based on its captured internal
failure path. Installation and validation details for 2329 are below.

Evidence: [20 September live results](2026-09-20-notification-live-results.md),
[22 September retest results](2026-09-22-notification-retest-results.md).
Instructions: [two focused follow-up retests](2026-09-22-notification-followup-retests.md)
and [original test script](2026-09-20-notification-live-test-prompt.md).
Fix evidence: [build 2327 fixes](2026-09-22-notification-followup-fixes.md).

## Current summary

- Build 2328: **2/2 live retests complete — 1 passed, 1 failed**. No more prompts
  pending from this run; first input now has a phone-confirmed cause and correction; fixed-phone live
  verification remains pending.
- Today's **five runs are finished: 3 passed, 1 partially passed, 1 failed**.
- Follow-up build 2327: **2 of 2 retests finished — 0 fully passed, 1 partial,
  1 failed**. No further desktop prompts remain from this run. First input
  notification is absent; unread reply restoration passes but read clearing fails.
- Original **19-scenario ledger: 6 passed, 2 partial, 1 failed, 10 blocked**.
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
| Initial input notification | 2328 live FAIL; diagnostic phone trace confirms the offline cached chat blocks request hydration. 2329 reuses and attaches that cache; exact native before/after check passes. Fresh fixed-phone pass pending. |
| Unread reply after force-stop/relaunch | Case B PASS on 2328: same native ID/text restored silently; actual shade tap opened the whole answer and cleared the notice; another restart left it absent. |
| New activity versus full-bottom reading | Older history correctly retained the notice. New activity showed the answer but did not clear; a full-bottom scroll did. Accepted bottom rule passes; shortcut behavior warrants UX follow-up. |

The original idle-reconnect watcher/replacement defect was fixed in `120868e`
(build 2325); LIVE-5/6 verified it. Build 2326 fixes were committed in `f291f59`.
Build 2327's two targeted changes have now been live-tested. Restoration works,
and build 2328 live-verifies the restored-read fix. The first-input failure still
reproduces; its fixed client race was not a complete explanation of the live issue.

## Original scenario checklist

| # | Scenario | Status |
| --- | --- | --- |
| 01 | Reply and reading | Passed for earlier ordinary replies: tap/latest-answer clearing and older-history retention/full-bottom clearing. Restored-reply read failure is tracked in 16 |
| 02 | Replacement and identical replies | Passed: exact identical text produced a fresh same-slot update |
| 03 | Foreground behavior | Passed: normal reply suppressed; real input notification allowed |
| 04 | Monitoring and interruption | Passed: live summary, lock-screen delivery, real desktop Stop and watcher shutdown |
| 05 | Three-question batch | Failed first delivery again on 2328 case A; real batch visible/answerable only after opening. Loaded-chat advancement/counts work |
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
| 16 | Restart / reconnect | Passed on 2328 case B: silent same-ID/text restoration, actual tap/latest-answer read clearing, and no resurrection after restart |
| 17 | Secure input | Blocked: no harmless generic dummy-data flow exposed by runtime |
| 18 | Session permission | Blocked: no real safe approval request |
| 19 | Always permission | Blocked: no real safe approval request; no permanent grant attempted |

Multi-chat/profile isolation and counts cannot be proved by these one-chat runs.

## Build 2329 confirmed-cause correction

Phone trace: actual working → waiting, one verified owner, then
`input-skipped-existing` for the offline cached chat and no resume attempt. The
saved-cache regression and native fixture reproduce the same failure before the
fix and pass after it. See the linked investigation for failed-read, newer-event
and user-navigation protection. No backend changes, new polling or compatibility
paths. Temporary tracing is removed from source.

**39 focused tests** and the full Flutter suite (**2,698 passed, 12 skipped**)
pass. Analysis is clean; **28 release-tooling tests** and version check pass.
Native Android old/fixed comparison passes; cached history is preserved and the
first useful notification arrives with monitoring shutdown.

Signed production ARM64 build **2329** installed with data preserved; phone
package readback confirms **1.0.1 / 23292**. Pinned certificate, package and
non-debuggable release verification pass. APK SHA-256:
`d354d43a09a106e5bce0660a049637981e9db2d4cafe2f545908701f2b0becd2`.
Temporary trace removed; emulator/captures stopped. No fresh fixed-phone live
pass is claimed. The diagnostic question
was not answered while phone availability was pending; check its current state
before the next live test. Do not assume it was answered or count it as a pass.

## Build 2328 live result

**A failed; B passed.** The later [live record](2026-09-22-notification-2328-live-results.md)
supersedes the pre-retest uncertainty below. There are no pending desktop prompts.
The first-input race fixed in 2328 is covered by a regression, but the complete
real first-delivery failure is still unexplained. Read clearing is live-verified.

## Build 2328 validation and installation

- Root causes: a stock empty approval response consumed the first question as a
  silent baseline; overlapping routes overwrote a shared visibility flag and
  prevented restored-answer read clearing. See the linked investigation for
  reproductions and why previous tests missed both failures.
- Complete Flutter suite: **2,688 passed, 12 skipped**. Analysis clean; all **28
  release-tooling tests**, version check and patch whitespace check pass.
- Android 16 emulator: first unopened three-question notification with useful
  content/Review and watcher shutdown; silent same-ID restoration; actual shade
  tap from the normal list clears the read reply; read and swiped replies stay
  absent after restart. These are isolated client fixtures, not live Hermes runs.
- Signed production ARM64 package verified: pinned certificate, non-debuggable,
  package identity and version **1.0.1 / 23282**. Data-preserving installation
  succeeded; physical phone version readback matches. Wing opens to Claw's
  connected chat list.
- APK SHA-256: `88f16e9cc1bec1dd5991f8c36f0a7579dd4e31eb7c025ed77e23c1f5a6c74bb6`.
- After installation/relaunch, the old stuck reply notice was already absent.
  Therefore its tap/read path could not be exercised on the phone. This absence
  is not proof that the fix cleared it; the exact reason was not captured.
  Generate a fresh reply for case B. No new Hermes prompt was sent in this step.
- Latest stock Hermes inspected at `fde4997f580c3480798fdf9c7e92c0079d6e03d6`.
  No backend changes, compatibility paths, polling loops or monitoring extensions.
- Temporary emulator stopped. Private captures remain under `/tmp`; no raw
  device logs or connection/session identifiers are included in the commit.

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
- Temporary emulator stopped. Subsequent real Hermes follow-up tests are now
  complete; [results](2026-09-22-notification-followup-live-results.md) supersede
  any claim that both fixes are live-verified. Capture stopped; phone on Home;
  stale case B notice retained as evidence. No test request remains pending.

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

1. Build 2329 is validated and installed. Run **A once** with the saved
   chat explicitly present after restart. Phone tracing has confirmed the exact
   guard; automated and native before/after checks pass. Check the diagnostic
   request state first. Preserve the live-verified restored-read fix; no unchanged
   repeat of B is required.
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
