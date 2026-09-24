# Notification test status

Updated **24 September 2026** during the remaining physical-phone tests.
Galaxy S23 Ultra / Android 16; Wing **2331**, version **1.0.1 / 23312**.
Latest notification live checks ran on 2331. The separate connection-status fix
is now installed; initial startup shows Connected. Live Once also passed after
watcher shutdown, without proving a specific pre-tap network restriction.

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
- Original **19-scenario ledger: 16 passed, 2 partial, 0 failed, 1 blocked**.
  Supported checks passing does not establish the blocked or uncovered branches.
- Sound is **confirmed working by the user**; no dedicated repeat is needed.
- Earlier trace approval timed out without execution; subsequent live Once,
  Deny, FIFO and Always-cancellation checks completed. Temporary Manual approval
  policy was authorized for this session. Smart was restored after the previous
  batch. **Smart was restored and read back after the final-four batch, with timeout
  300 and the allowlist unchanged. Original font scale 1.0 remains restored.** No backend code,
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
| 09 | Mixed input priority | Partial: isolated native QA retains approval ahead of question and newer answer, then Deny advances to the question. Stock same-chat combination remains ungenerated; final question-to-answer branch not covered in this run |
| 10 | Swipe dismissal | Passed for stock sequential requests: user dismissed A, answered A on desktop, and confirmed a new B notification appeared. Earlier reconnect/restart retention also passed. Simultaneously pending requests are a separate synthetic coverage limit, not demonstrated by this sequence |
| 11 | Long command / large-text approval layout | Passed for inspected layouts: clipped command requires full review; four actions remain readable in two rows at 200% on physical Samsung light shade and isolated Android dark shade. Review controls reachable; warning-below-fold usability issue remains for the fix pass |
| 12 | Hidden previews / channels | Passed for questions/counts and category diagnostics; approval privacy branch blocked |
| 13 | Unlocking approval actions | Passed: securely locked phone hides actions; normal unlock exposes choices and explicit Once succeeds. User confirmed this is the intended behavior; cancel-authentication from a hidden button is not a required test |
| 14 | Offline / stale approval actions | Partial: prior isolated native QA verified failure visibility, pending retention and no RPC while recovery fails. Live expired request clears on reconnect; expired Session tap also cleared its notice without execution. Physical outage attempt invalid because capture/helper stopped before any verified action; live offline decision/retry not proven |
| 15 | Desktop resolution | Passed: 24 September question cleared/replaced after desktop answer while Wing stayed on Home and watcher continued for other work; observation does not isolate timer versus streamed updates |
| 16 | Restart / reconnect | Passed on 2328 case B: silent same-ID/text restoration, actual tap/latest-answer read clearing, and no resurrection after restart |
| 17 | Secure input | Blocked: no harmless generic dummy-data flow exposed by runtime |
| 18 | Session permission | Passed on 2331 in a new disposable chat: user tapped native Session; Hermes reports A and B executed, B without another approval; same-slot result notice agrees. Scope is broad execute_code within that test session, not a print-specific grant |
| 19 | Always permission | Passed for the authorized confirmation/cancellation flow on 2330: native Always opens correct review, Cancel retains the pending request, subsequent Deny accepted. Broad permanent grant deliberately not attempted |


Multi-chat/profile isolation and counts cannot be proved by these one-chat runs.

## Installed build and validation

- Current installed update **2331 / 23312**, source `d6cf733`, fixes connection
  recovery membership. Full suite **2,708 passed / 12 skipped**, clean analysis,
  signed non-debuggable ARM64 verification and data-preserving install passed.
  [Investigation and deployment evidence](2026-09-24-connection-status-investigation.md).
- Earlier notification-specific release evidence follows; these older build
  numbers are historical, not the currently installed package.

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

1. Real Once, Deny, FIFO, Session and Always-cancellation checks completed.
   Secure input remains blocked by lack of a generated safe stock flow.
   Permanent grant acceptance remains outside the authorized cancellation test.
2. Cover safely supported concurrent-input and already-running-watcher branches,
   plus multi-chat/profile behavior, when resuming broader testing.
3. Review the previously documented New activity extra-scroll UX separately.
4. Ask Hermes to clean up the remaining disposable test parent when requested:
   `/home/tarkil/.hermes/cache/scratch/wing-notification-test-CZeiJPit`.

Private captures remain under `/tmp`; none are committed.

New observation awaiting investigation: duplicate monitoring cards appeared in Samsung’s expanded Wing group during the 24 September run. See the live results for evidence and scope.

## 2332 follow-up

The duplicate review, monitoring-card and recovered-preview issues are fixed in
[2332 review fixes](2026-09-24-notification-review-fixes.md). Automated and native
evidence, limitations, and the exact phone retests are recorded there. Phone
still has 2331 until deployment is confirmed; do not treat build completion as
a device test pass.
