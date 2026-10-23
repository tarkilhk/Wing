# Chat with bots and coordinate discussions

Find a bot across saved instances, open its chat or group discussion, manage its identity, and view its desktop; take control only after ownership is confirmed, then hand it back.

Feature ID: `bots`.

## Sub-features

- `bots.chat` — Open the exact bot conversation.
- `bots.groups` — Read and manage a hosted discussion.
- Bot and group approvals use the same command review as normal chats: the review starts with the exact command visible in the transcript, request details expand separately, and the available icon actions reflect that request’s allowed scopes. While reading older messages, the waiting status remains visible and Latest returns to the review.
- `bots.desktop` — Observe passively, take confirmed control and hand it back. Landscape places the agent panel beside the desktop; portrait places it below. Tap clicks, one finger pans the magnified view, two fingers scroll, pinch zooms, hold right-clicks, and double-tap/hold drags. A persistent side strip also scrolls. The four main icons open the native keyboard, paste the phone clipboard, reveal more controls, and change control ownership. More holds only utility actions such as fullscreen, panel visibility, refresh, screen power and gesture help; it does not duplicate zoom or click gestures. Special keys and one-shot modifiers accompany direct typing. Paste announces plain UTF-8 text, invokes Ctrl-V without pressing Enter, and supplies the text when the remote application requests it. Its pending indicator lasts through transfer; an unaccepted paste shows a retryable error.
- When opened from a chat, the panel shows its latest assistant message or pending request. Open Conversation to read or queue a message without consuming the main chat draft. Formal approvals and private input are answered in the main chat. Handback can include a note and continuation request; the lease is released before the message is queued. A failed message keeps the note and reports that control was already returned. A screen opened directly from the roster has no selected conversation and only returns control.

## How to get to it (user POV)

Choose Bots in the drawer. Use the Bots and Groups tabs. Tap a name or preview for chat, an avatar for appearance, or the row menu for Bot settings and View screen. Long-press a profile icon in Chats for Bot Chat.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/bots_contract_test.dart test/gateway_approval_panel_test.dart test/bot_group_view_test.dart test/bot_group_history_test.dart test/bot_display_client_test.dart test/bot_display_viewport_test.dart test/bot_screen_session_test.dart test/bot_screen_view_test.dart test/profile_composer_queue_test.dart
  ```

- **Android `bots`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py bots --output build/feature-verification/bots
  ```

## Gotchas

Bot Chat and group discussions have different return destinations. Live desktop control needs a running stock desktop and a confirmed lease; fixture lease checks do not establish a real desktop session.

Clipboard, gesture and handoff tests use the production RFB parser and lease owner. Negotiation uses the stock RFB ExtendedClipboard identifier (0xC0A1E5CE), with a fixture that distinguishes it from ExtendedDesktopSize. They cover Unicode/multiline data, no automatic Enter, loss of control during clipboard read or the remote request, delayed/absent remote requests, visible pending operations and retained notes on failure. The native Bots family verifies Android entry paths; it does not exercise a deployed desktop. `integration_test/bot_screen_live_test.dart` remains opt-in with an explicitly approved live bot and owned emulator.
