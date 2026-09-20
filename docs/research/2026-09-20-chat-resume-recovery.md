# Automatic recovery after a session-resume internal error

Inspected upstream Hermes main on 2026-09-20 at
`c7e165a06870bfc677f7d9752f2f969896acd837`.

Stock contract:

- [WebSocket dispatcher](https://github.com/NousResearch/hermes-agent/blob/c7e165a06870bfc677f7d9752f2f969896acd837/tui_gateway/ws.py#L359-L365)
  returns JSON-RPC `-32603` (`internal error`) when dispatch raises.
- [Session resume](https://github.com/NousResearch/hermes-agent/blob/c7e165a06870bfc677f7d9752f2f969896acd837/tui_gateway/methods_session.py#L856)
  reattaches a stored conversation. Its own caught reconstruction failures use
  `5000`, which Wing already retries.
- [Reattachment guard](https://github.com/NousResearch/hermes-agent/blob/c7e165a06870bfc677f7d9752f2f969896acd837/tui_gateway/session_lifecycle.py#L691-L699)
  supplies the existing disconnect-race responses Wing already retries.

Wing treated `session.resume` / `-32603` as permanent, leaving a restored chat
on “Couldn’t reopen this chat. Retry to continue.” The regression test reproduced
that exact banner before the fix. The screenshot alone does not identify the
original server error, and the available device logs did not establish it.

The client routes this response through its reconnect loop: retry after 1, 2, 4,
8 and 16 seconds, then wait for app/screen focus, network change or explicit Retry.
Returning to Wing, navigating back to its chat route, or selecting Chats from
another destination retries immediately. Focus events share in-flight recovery;
covered routes do not reconnect on an unrelated app-resume event. There is no
perpetual 30-second polling. Foreground recovery and notification reopening share
the classification.
The draft and conversation identity stay intact. This classification does not
apply to `prompt.submit`; recovery must not replay a submitted message.
Missing sessions, invalid parameters and rejected sign-in remain explicit errors.
No backend modification, alternate API or compatibility path is needed.

Regression coverage lives in `profile_notification_recovery_test.dart` and
`workspace_connection_failure_test.dart`, including foreground recovery, automatic
notification reopening, retained drafts and exclusion of prompt submission.

Focus-driven recovery rechecked the unchanged `session.resume` and WS `-32603`
contracts at upstream main `07c1953ea16d4c6990efb78d3da801e379ca86ff` on
2026-09-20. `profile_focus_recovery_test.dart` covers Flutter app lifecycle,
route visibility, destination selection and overlapping focus events.
