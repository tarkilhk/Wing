# Transcript display projection

Audited against the installed official Hermes Desktop source at NousResearch/hermes-agent commit `e16f686706b1e0d5334fd1ae82190058d2a19694` on 2026-09-14. The source files below have no local changes against that commit.

Hermes can store internal deliveries with the user role. Android projects their verified envelopes as compact notices or hidden context, preserving the raw history. Its process-batch projection also validates untyped producer batches before reusing the per-process display rule; it does not match a generic instruction paragraph.

| Desktop source / condition | Android presentation |
| --- | --- |
| `hydration.ts`: `hidden` | No transcript row or search result |
| `hydration.ts`: `async_delegation_complete` | Compact completion notice and collapsed result; no preamble, goals or transcript footer |
| `hydration.ts`: `model_switch`, `auto_continue`, `personality_switch` | Compact timeline labels |
| `user-message.tsx`: complete `[IMPORTANT: Background process ...]` envelope | Headline with collapsed Output; no human bubble, Copy or Edit controls |
| `user-message.tsx`: `Message from` with optional robot/handle, or legacy `[Message from agent '...']` | Attributed notice with collapsed message; no human controls |
| `assistant-message.tsx`: first settled reply following an agent delivery | Replied to sender, with collapsed reply; streaming content remains visible |
| shared `skill-scaffold.ts`: single or bundled skill activation | Original slash invocation and instruction, without the skill body/runtime note |
| `hydration.ts`: attached context and context warnings | User prose with missing references restored once; expanded model context removed |
| `system-message.tsx`: `review:`, `steer:`, `slash:` | Existing review/steering rows and compact slash-command status |
| `system-message.tsx`: other system text | Compact status text without assistant-style header or Copy control |
| Gateway history: user `[System:` marker | Existing hidden-marker behavior retained |

Source references: [hydration](https://github.com/NousResearch/hermes-agent/blob/e16f686706b1e0d5334fd1ae82190058d2a19694/apps/desktop/src/lib/chat-messages/hydration.ts), [user renderer](https://github.com/NousResearch/hermes-agent/blob/e16f686706b1e0d5334fd1ae82190058d2a19694/apps/desktop/src/components/assistant-ui/thread/user-message.tsx), [assistant renderer](https://github.com/NousResearch/hermes-agent/blob/e16f686706b1e0d5334fd1ae82190058d2a19694/apps/desktop/src/components/assistant-ui/thread/assistant-message.tsx), [system renderer](https://github.com/NousResearch/hermes-agent/blob/e16f686706b1e0d5334fd1ae82190058d2a19694/apps/desktop/src/components/assistant-ui/thread/system-message.tsx), [skill projection](https://github.com/NousResearch/hermes-agent/blob/e16f686706b1e0d5334fd1ae82190058d2a19694/apps/shared/src/skill-scaffold.ts).

These are producer-envelope matches copied from Desktop, not a broad technical-keyword filter. Quoted envelopes and ordinary technical discussion remain visible. Untyped delegation text retains Desktop's normal fallback. Unknown future backend formats are not silently discarded.

Find in chat shares delivery and skill projection, preserving useful output while removing wrappers. Raw history, durable row IDs, pagination and user ordinal counts stay intact. Edit, Restore checkpoint and regeneration reject injected deliveries before submitting a prompt. Tool calls/results and reasoning use the shared ordered Activity Timeline and detail readers; this projection does not add sidecar answer hydration.

Human prompts use right-aligned bubbles with a local date and Edit/Restore
footer. Copy sits outside the upper-right corner. Assistant prose has no avatar
or author-name row; its upper-right Copy action shares the Activity header when
present, and its date and answer actions follow the content. Internal notices
retain their compact presentation and never acquire human saved-message actions.
See [Conversation preservation](DESIGN_SYSTEM.md#conversation-preservation).

Regression fixtures in `test/internal_message_visibility_test.dart` cover the reported process envelope, current/legacy agent formats, single/bundled skills, Desktop negative cases, phone/tablet widths, expanded output, search, saved history refresh, hidden rows and assistant reply boundaries. `test/answer_versions_test.dart` verifies that edit/regeneration cannot submit an internal delivery. Existing steering, review, activity, search and saved-answer tests cover the retained branches. This is a client projection fix; the backend is unchanged.

## Background process heartbeats

Standalone user-role process heartbeats are hidden from the transcript and chat
search, and cannot become editable prompts. The client recognizes the complete
`[Background process … heartbeat #… — still running after …]` envelope, including
its command and output boundaries. Quoted examples, partial envelopes, assistant
text and clean server display projections stay visible. Raw history and rewind
ordinals remain intact.

Verified against stock Hermes
[`format_process_notification`](https://github.com/NousResearch/hermes-agent/blob/e33fd7e09b42c50e347cd32564a4a83ad5c4a97b/tools/process_registry_notifications.py)
at upstream commit `e33fd7e09b42c50e347cd32564a4a83ad5c4a97b`.

## Task snapshots after compression

The producer at Hermes revision `498abb677ec39ea3ae9f8f5ed60e7def6bc47e70` can append task context in standalone user rows or inside a real user message. The standalone rows are not new human prompts.

The shared hidden-message projection honors `display_kind: hidden` and a user row's boolean `_todo_snapshot_synthetic`. Its untyped fallback requires the exact producer header on the first line, immediately followed by a task marker and nonempty text, with CRLF normalized. Clean `display_content` takes precedence. Ordinary lists, assistant content, quotes, partial headers and real messages with appended reminders remain visible.

An exact untyped copy of the producer envelope is inherently ambiguous; consistent server display metadata would remove that ambiguity. Do not strip embedded text from human messages. `test/task_snapshot_visibility_test.dart` and the internal-message tests cover display, search, editing and unchanged raw identities.


## Command feedback

Verified against upstream main `8a3ede1be0618462e3e5e15e9ab4bdb8ae82af96`
on 28 September 2026: desktop
[`use-prompt-actions/slash.ts`](https://github.com/NousResearch/hermes-agent/blob/8a3ede1be0618462e3e5e15e9ab4bdb8ae82af96/apps/desktop/src/app/session/hooks/use-prompt-actions/slash.ts),
[`system-message.tsx`](https://github.com/NousResearch/hermes-agent/blob/8a3ede1be0618462e3e5e15e9ab4bdb8ae82af96/apps/desktop/src/components/assistant-ui/thread/system-message.tsx),
and stock [`config.set`](https://github.com/NousResearch/hermes-agent/blob/8a3ede1be0618462e3e5e15e9ab4bdb8ae82af96/tui_gateway/methods_config_set.py).

Slash output, including approval-mode changes and session YOLO confirmations,
is client-owned system text in the conversation. It uses quiet metadata styling,
centered for single-line output and left-aligned for multiline output. Later
messages follow it; there is no separate command-output footer. History refreshes
retain each local entry beside its neighboring messages without counting it in
server pagination or sending it as model input. Repeating a command produces a
new entry even when its wording is identical.

Desktop uses temporary notification feedback for YOLO before creating a session.
Wing creates its runtime when New chat opens, so the equivalent empty, unsubmitted
chat uses a five-second snackbar after the server acknowledges the toggle. An
existing conversation or running turn receives an inline confirmation instead.
Failures keep the existing recoverable error presentation. All changes are in the
Android client; approval ownership and the stock RPC contract are unchanged.

`test/command_feedback_test.dart` covers ordering across refreshes, repeated
commands, notification expiry, and phone layouts in both themes at normal and
200% text. Its optional `CAPTURE_COMMAND_FEEDBACK` captures use
`CAPTURE_FONT_DIR=<Flutter SDK>/bin/cache/artifacts/material_fonts` and write to
`build/command-feedback-review/`.
