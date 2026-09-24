# Notification review and recovery fixes — 2332

## Observed causes

- Notification review opened a chat route before its dialog and dismissed the
  dialog before sending the decision. Failed sends exposed another approval
  card underneath. The dialog also allowed confirmation while offline.
- The foreground monitoring service posted ID 214601 and a duplicate summary,
  ID 214602, with the same content. The isolated Android reproduction returned
  two active monitoring records. This was not two independent watchers.
- Reconnect and pending-journal restoration read reply history but deliberately
  posted the generic `Chat updated` projection. A regression returned “Open the
  chat to see the outcome” despite a known recovered answer. Unopened completed
  chats did not fetch a reply preview at all.
- Review put scope after a long command/backend description. The backend prose
  describes one-shot execution, which is not the scope of Session or Always.

Current stock Hermes HEAD verified at
`58c896ea4ebaff5425a068f461b6c6fedadb8b40`. Approval schema and execute_code source
were inspected read-only. No backend changes, custom API, text-based scope
inference, new recurring polling, or compatibility layer.

## Changes

One review dialog overlays the current screen. Cold requests are loaded without
selecting a second chat route. Successful acknowledgement closes review; failed
sends keep it open with explicit uncertainty. Known offline state disables the
confirmation and says “Offline—approval not sent. Reconnect to retry.” Recovery
never replays a decision. Removed/replaced requests disable the old dialog.

Scope is pinned above the independently scrolling command. Backend prose remains
available under “Hermes request details”; it is not parsed or rewritten into a
permission decision. Once, Session and Always use the actual selected choice.
Studio title typography and shorter Always heading preserve space at 200% text.

The alternative of navigating to the inline chat card was considered: it would
remove the popup, but would also change every notification action into chat
navigation and need an additional permanent-scope confirmation. Keeping one
explicit dialog preserves notification action behavior and avoids that extra
navigation. Existing Studio colors, type and control tokens are used.

Monitoring uses its single foreground notification. The redundant summary is
cancelled instead of republished. Title/count updates retain the same ID.

Recovered results use official history rows and the existing answer projection;
when available the message ID is retained for read targeting. Failed history
reads do not replace a useful notice with stale text. A known prior answer is
retained when recovery yields no newer answer. Unopened working-to-idle
transitions fetch one history page, only at that observed transition.

## Verification

- Red regressions reproduced extra chat navigation and loss of recovered text.
- Full suite: **2,715 passed / 12 intentional skips** on the main fixes.
- Subsequent focused checks passed on final refinements: review/routing/error/
  scope/recovered answer; additional cold-request and unopened-answer tests pass.
- Final static analysis: clean. Diff whitespace validation: clean.
- Android emulator: two monitoring records before the change, one afterward.
  A real notification action opened one dialog above the chat list. Simulated
  offline state displayed the explicit message, disabled Allow once, and sent
  no approval RPC. A subsequent native reconnect attempt was inconclusive after
  the emulator/ADB connection disappeared; do not claim a native retry pass.
  Automated widget/controller tests verify failed-send retention and explicit
  retry with no automatic decision on recovery.
- Actual Studio dialog captures inspected in light/dark themes at 100% and 200%.
  Scope and confirmation controls remain visible; long commands scroll.
- Production 2332 / 23322 built as signed, non-debuggable ARM64. Final APK SHA-256:
  `b97b84376ed03dfc4ef78d0948c18892b0ca3cea05bbb230a29335bdac809fb4`. Installed on the physical phone with app data preserved. Package version
  read back as 23322; launch showed Chats and Claw, Connected. This is a
  deployment smoke check; the phone scenarios below still require retesting.

Private captures/logs are under `/tmp/wing-notification-fixes*` and are not committed.

## Phone checks after installation

1. User-operated offline approval, then reconnect: one review surface, visible
   offline state, no automatic approval, explicit retry succeeds.
2. Background running task: exactly one Watching card in the expanded shade;
   count/text update and card disappears when no work remains.
3. Complete a desktop task across phone reconnection: useful latest answer text
   survives and reading that answer clears its notification.
4. Review Session/Always with a long command at enlarged text. Inspect scope and
   cancel Always; no permanent grant is needed for this visual check.

Mixed same-chat input priority remains a separately recorded synthetic/live
coverage limit; these fixes do not convert that scenario into a verified live pass.

## Physical phone combined retest — 18:09–18:15 Singapore

WING-RECOVERY-2332 ran a desktop 120-second terminal sleep and returned the
requested answer while the user had disabled phone Wi-Fi and mobile data.
Before the outage, native records showed one app-owned foreground monitoring
notification (214601), no former duplicate 214602, and a running foreground
service. Its summary was Watching 2 chats / 2 working; unrelated work was also
active, so this does not isolate the target chat or prove correct count updates.
Android also retained an automatic Wing grouping summary; this is not a second
app-owned Watching card.

After connectivity was restored, the user reported no target reply notification.
Read-only inspection before reopening Wing found its process alive (PID 9228),
no monitoring service, and no target reply notification. Opening only the Chats
list showed Connected but still did not produce the target notification. The
latest activity was under Run WING-OFFLINE-RETEST execution check; the older
Manually test Wing Android notifications chat had not changed. No target answer
was opened/read during this inspection.

Result: duplicate app-owned monitor removal verified in native records;
background recovery delivery did not pass, and recovered-preview/read-clear
checks remain unverified. Logs captured after reconnection did not retain the
relevant stop event. Do not claim that the app was killed or that connectivity
loss itself is already proven to be the stop trigger. Investigate why known
unfinished work ceased to retain monitoring, and whether the actual target chat
was tracked. User confirmed the intended behavior: connectivity loss must not
stop monitoring of known unfinished work; retain it while reconnecting until the
outcome can be confirmed. No production changes made during this retest.

Private evidence: /tmp/wing-notification-fixes/recovery2332-before-*.txt,
recovery2332-after-*.txt, and recovery2332-reopened-notifications.txt.

### Session wording at enlarged text — user screenshot 18:46

Physical-phone screenshot confirms the Session review shows “Allow matching
commands for this session.” above the long command at font scale 2.0. Cancel
and Allow for session are visible; confirmation is disabled and the explicit
“Offline—approval not sent. Reconnect to retry.” message is present. The dialog
overlays the Chats list, with no duplicate approval chat route underneath.
Session layout branch passes by screenshot. This alone does not prove actual
network availability, absence of automatic retry, or successful online retry.
Always review remains pending. Wireless ADB could not connect to supplied port
33139; user is operating manually. Font scale 2.0 and temporary Claw/default
Manual mode still require restoration after the remaining tests.

User subsequently confirmed the Always permanent-scope warning is visible.
Together with the Session screenshot, test 4 scope visibility passes at enlarged
text. Asked user to cancel Always and report whether the desktop request remains
pending so the offline test can reuse it if still valid. No permanent permission
grant was requested. Cleanup of temporary font scale and Manual mode is pending.

### Final manual offline approval retest — PASS for review route

User generated a fresh WING-OFFLINE-2332 approval after the scope request timed
out. While offline, notification Once opened the single review popup with Allow
once disabled. User restored connectivity with the popup open: the confirmation
became enabled, desktop still showed the request pending, and only the explicit
Allow once tap approved it successfully and removed the desktop request.
User-reported sequence verifies no automatic approval on reconnect and successful
manual retry. This is the reviewed-command route, not a separate direct-action
branch test; native notification removal after success was not separately
reported in this run.

Four planned follow-up checks: (1) offline review/retry PASS by user operation;
(2) one app-owned monitor record verified, but complete lifecycle/count changes
not independently proven; (3) outage recovery delivery FAILED and therefore
preview/read-clear unverified; (4) Session/Always large-text scopes PASS.
Investigation reproduced lost completion tracking across disconnect/failed reads:
see 2026-09-24-monitoring-outage-investigation.md. No fix deployed for that issue.

Cleanup remains outstanding: wireless debugging port 33139 refused connection
after user restored phone connectivity. Requested current address to restore
font scale 1.0 and Claw/default Smart approval mode, preserving timeout 300 and
the existing allowlist.

Cleanup update: connected on port 36901 and restored/read back font scale 1.0.
Navigated Claw/default approval policy, selected Smart, and verified unchanged
timeout 300 and allowlist before Save. Wireless debugging went offline before
the Save tap was sent; Smart is selected but not yet confirmed saved. Asked
user to tap Save on the current screen and confirm No unsaved changes.

Cleanup complete: user confirmed the selected Smart approval mode is now saved.
Font scale 1.0 was previously restored and read back remotely. Smart save is
user-confirmed; no subsequent remote readback was available.

Final follow-up: the outage finding was fixed and deployed in 2333. The new-chat
WING-FINAL-2333 phone retest passed: exact target working and single foreground
monitor verified remotely before outage; user confirmed reconnecting status,
exact recovered reply, watcher shutdown, and clearing on reaching the answer.
See 2026-09-24-monitoring-outage-investigation.md. All requested fix retests are
complete; earlier optional/capability coverage limits remain unchanged.
