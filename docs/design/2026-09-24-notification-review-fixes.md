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
  `b97b84376ed03dfc4ef78d0948c18892b0ca3cea05bbb230a29335bdac809fb4`. Deployment awaits the phone's current debugging port.

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
