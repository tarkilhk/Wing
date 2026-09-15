# Notification proposal

Prepared with the improve skill on 2026-09-16; refined after the owner requested
simpler scope. Implemented and verified on 2026-09-16.

| Plan | Priority | Effort | Dependencies | Status |
| --- | --- | --- | --- | --- |
| [001: Rich chat notifications](001-rich-chat-notifications.md) | P1 | M | None | DONE |

## Selected scope

One layout, three categories: Update, Input needed, Work stopped. Show the chat
name, a useful excerpt and expanded text. Tapping opens the chat. One message
preview switch; lock-screen visibility follows private notification policy and
Android settings.

## Deferred ideas

Custom grouping, message-level navigation, distinct sounds, image previews,
inline actions, per-request lifecycles and specialized task presentations are
outside acceptance criteria. They are not a promised follow-up phase.

Reviewed notification production, content models, settings, delivery docs and
routing/test seams. This was not a whole-repository audit. Validation: 1,769 tests passed (10 skipped),
static analysis clean, native emulator checks passed, normal debug APK built.
