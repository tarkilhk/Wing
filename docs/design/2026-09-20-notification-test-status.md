# Notification test status

Updated **24 September 2026** during the remaining physical-phone tests.
Galaxy S23 Ultra / Android 16; Wing **2330**, version **1.0.1 / 23302**.
Clean fix installed; live Once passed with monitoring active. The separate
idle/disconnected recovery regression remains pending.

**Both bug-fix follow-ups now pass. Zero focused retests remain.**
[Final live result](2026-09-23-notification-final-live-result.md).

[24 September live session](2026-09-24-notification-live-results.md): the direct-action failure is traced and fixed in 2330; automated/native QA and live Once passed; real-phone idle/disconnected recovery retest pending. Earlier focused fixes remain passed.

## Current summary

- **A — First question after restarting with a saved chat: PASS on 2329.**
  Notification arrived before opening the chat with 3 questions and actual
  question/choices. Review opened the correct form; one slot advanced 3→2→1;
  all answers were accepted and the notice cleared. Monitoring stopped normally.
- **B — Restored reply read clearing: PASS on 2328.** Same reply/ID restored
  silently; actual shade tap opened the latest answer and cleared the notice;
  another restart kept it absent. No unchanged repeat was needed.
- Original **19-scenario ledger: 11 passed, 2 partial, 0 failed, 6 blocked**.
  Supported checks passing does not establish the blocked or uncovered branches.
- Sound is **confirmed working by the user**; no dedicated repeat is needed.
- Latest trace approval timed out without execution. Temporary Manual approval
  policy was authorized for this session. Smart was restored after the trace;
  **Manual remains temporarily enabled for the continuing approval test batch.
  Restore Smart afterward.** No backend,
  credential, authentication, channel or battery-setting changes. See the live
  session document for the diagnostic-build replacement and current deployment.

## Confirmed fixes

| Issue | Final evidence |
| --- | --- |
| Idle-reconnect watcher/replacement | Fixed in 2325 (`120868e`); LIVE-5/6 verified it |
| Remaining-question count | 2326 count rendering and hidden-preview behavior passed; final 2329 live run confirms 3→2→1 |
| Stale Needs input after desktop resolution | 2326 live resolution/reconnect and continued-work cleanup passed |
| Missing first input with a saved chat | 2329 (`8dae23b`) reuses and attaches the cached chat; actual phone trace established the guard, native before/after reproduced it, final phone run passed |
| Restored reply remains after reading | 2328 route-visibility fix; actual phone tap/read/restart passed |

Earlier New activity behavior required an extra full-bottom scroll in one run.
The accepted bottom rule passed; the shortcut's extra scroll remains a separate
UX observation, not an outstanding failure of these two focused retests.

## Original scenario checklist

| # | Scenario | Status |
| --- | --- | --- |
| 01 | Reply and reading | Passed: ordinary tap/latest-answer clearing and older-history retention/full-bottom clearing; restored-reply path also passes in 16 |
| 02 | Replacement and identical replies | Passed: exact identical text produced a fresh same-slot update |
| 03 | Foreground behavior | Passed: normal reply suppressed; real input notification allowed |
| 04 | Monitoring and interruption | Passed: live summary, lock-screen delivery, real desktop Stop and watcher shutdown |
| 05 | Three-question batch | Passed on 2329: first delivery before opening after a saved-cache restart, useful text/options/Review, same-slot 3→2→1 and successful completion |
| 06 | Once | Passed on 2330: real pending print-only approval resolved after the exact notification Once tap and same-slot result arrived. Other chats kept monitoring active; the disconnected recovery regression is separately pending |
| 07 | Deny | Passed on 2330: actual notification Deny cleared the request; same-slot result confirmed no execution or retry |
| 08 | FIFO approvals | Passed on 2330 short-path repeat: two simultaneous requests; same slot advances 2→1→result; a approved Once, b denied with no execution. Two-item live sample, not the original three-item example |
| 09 | Mixed input priority | Blocked: no real safe approval request; concurrency unverified |
| 10 | Swipe dismissal | Partial: preserved across reconnect and force-stop/relaunch; concurrent new-request branch uncovered |
| 11 | Long command / large-text approval layout | Partial on 2330: clipped command correctly requires full in-chat review before decision; enlarged-font branch pending |
| 12 | Hidden previews / channels | Passed for questions/counts and category diagnostics; approval privacy branch blocked |
| 13 | Unlocking approval actions | Blocked: no real safe approval request |
| 14 | Offline / stale approval actions | Blocked: no real safe approval request |
| 15 | Desktop resolution | Passed: 24 September question cleared/replaced after desktop answer while Wing stayed on Home and watcher continued for other work; observation does not isolate timer versus streamed updates |
| 16 | Restart / reconnect | Passed on 2328 case B: silent same-ID/text restoration, actual tap/latest-answer read clearing, and no resurrection after restart |
| 17 | Secure input | Blocked: no harmless generic dummy-data flow exposed by runtime |
| 18 | Session permission | Blocked: no real safe approval request |
| 19 | Always permission | Blocked: no real safe approval request; no permanent grant attempted |


Multi-chat/profile isolation and counts cannot be proved by these one-chat runs.

## Installed build and validation

- Production fix: `8dae23b`; signed build **2329**, Android version code **23292**.
  Data-preserving installation and physical phone package readback verified.
- **39 focused tests**, complete Flutter suite **2,698 passed / 12 skipped**,
  clean static analysis, **28 release-tooling tests**, version/whitespace checks.
- Exact saved-cache Android fixture: old code fails with zero resume calls and
  no notice; fixed code posts useful three-question input, preserves cached
  history and stops monitoring. Race tests protect newer events and navigation,
  failed reads, ownership mismatch and resolved requests.
- Physical-phone final pass: [23 September result](2026-09-23-notification-final-live-result.md).
- Signed ARM64-only, non-debuggable package verified against the pinned release
  certificate. APK SHA-256:
  `d354d43a09a106e5bce0660a049637981e9db2d4cafe2f545908701f2b0becd2`.
- Stock Hermes inspected at `95f20517c25ee418da5337f4ead347008baaa2b3`.
  No backend change, compatibility path, extra polling or monitoring extension.
- Temporary diagnosis trace was removed before production installation.

## Historical evidence

Failed runs remain recorded; their outcomes are not rewritten into passes:

- [20 September live tests](2026-09-20-notification-live-results.md)
- [22 September five retests](2026-09-22-notification-retest-results.md)
- [2327 follow-ups: A failed, B partial](2026-09-22-notification-followup-live-results.md)
- [2328 follow-ups: A failed, B passed](2026-09-22-notification-2328-live-results.md)
- [Earlier race/visibility investigation](2026-09-22-notification-root-causes.md)
- [Phone-confirmed saved-cache cause and correction](2026-09-22-notification-cached-chat-investigation.md)

## Remaining optional / capability-dependent coverage

1. Actual approval tests remain blocked until a genuine harmless request is
   available under the deployed policy. Do not change policy or make riskier
   requests solely to generate approvals. Permanent grants require explicit
   instruction and a verified narrow scope.
2. Cover safely supported concurrent-input and already-running-watcher branches,
   plus multi-chat/profile behavior, when resuming broader testing.
3. Review the previously documented New activity extra-scroll UX separately.
4. Ask Hermes to clean up the remaining disposable test parent when requested:
   `/home/tarkil/.hermes/cache/scratch/wing-notification-test-CZeiJPit`.

Private captures remain under `/tmp`; none are committed.

New observation awaiting investigation: duplicate monitoring cards appeared in Samsung’s expanded Wing group during the 24 September run. See the live results for evidence and scope.
