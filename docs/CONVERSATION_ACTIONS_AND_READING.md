# Conversations and saved-answer actions

## Drafts and sending

Draft text and staged files persist per connection identity, canonical profile and durable chat. Navigation and restart preserve unsent work. Missing local files must not erase the text. An accepted send clears only its submitted snapshot; newer typing and attachments stay in the composer.

Restore server history and status before continuing work. Do not automatically resend after an uncertain acknowledgement. Normal sends still have a process-death window where a retained draft can return without an uncertainty warning; check history before resending. See [issue #3](https://github.com/tarkilhk/Wing/issues/3).

Saved drafts remain discoverable when their chat is absent from a loaded server page. Recover to a new chat only after a confirmed missing-session result, not an ambiguous request failure. Move the draft in one durable storage operation, reset old upload receipts, pause queues and require explicit Send.

The idle action is Send. Busy actions and accessible alternatives follow [Composer actions](COMPOSER_ACTION_GESTURE.md). [Queues](SUPERVISION_AND_QUEUES.md) remain separate from the current draft.

## Edit, regenerate and fork

Edit targets a saved user row by durable identity, verifies fresh history and confirms replacing that turn and later history. It preserves unrelated composer work and pauses queued follow-ups. Internal deliveries must not become editable human prompts.

Use the pencil beside a sent user message. Its controls remain beside the bubble:
local `HH:mm` at the top and the icon-only Edit then Copy row at the bottom,
with 4 dp edge insets. Both share the center of the space beside the wider bubble. Fork and Regenerate remain
answer actions, with no additional edit button. Find's separate history view
stays read-only. The compact Studio editor has a close control, a scrollable
message and history-replacement warning, and a fixed resend footer above the
keyboard. It starts with the displayed prompt and enables
Replace and resend only for a nonempty correction. Unchanged text does not
submit or pause the queue. Editing requires a connected, idle chat; the workspace
controller owns that admission for both the button and the command. The phone
keeps its explicit history-replacement confirmation and retains a rejected
correction for retry.

Verified against upstream main `aa74e184ea779994af642ab4f888e10a95415d90`
on 9 October 2026: desktop `user-message.tsx`, `user-edit-composer.tsx`,
`use-prompt-actions/index.ts` and `rewind.ts`, plus stock
`tui_gateway/methods_prompt.py`. Desktop opens an inline editor from the user
bubble and can interrupt an active turn before resubmission. Wing uses its
confirmation editor in an idle chat. Both address the saved row through
`prompt.submit` with `truncate_before_row_id`, `confirm_truncate` and explicit
empty-history confirmation. Wing never guesses a truncation ordinal or falls
back to an ordinary send when the saved row cannot be verified.

`test/saved_message_actions_test.dart` guards sent-message-only entry points,
keyboard-safe editing in both themes at 320 dp/200% text, unchanged submissions,
queue preservation, history replacement, refusal and uncertain
acknowledgements. Static layout checks cannot establish captured-row admission
or asynchronous ordering. `test/message_timestamp_test.dart` checks the
48 × 48 dp action targets, top/bottom insets and shared horizontal
centering in both themes at normal and enlarged text, including disabled Edit
and corner taps on Copy in short messages. The saved-edit suite checks Copy’s
outer corner in the real workspace transcript before opening Edit.
The layout regression fails against the original message renderer and passes
with the revised controls. Rendered text size, geometry and keyboard insets
require behavioral checks; a source linter cannot establish their reachability.

Regenerate replaces the answer in the same chat. Branch/Fork creates a separate chat with an explicit boundary. Ordinary regenerated replacement and fork reopen work through existing APIs; synchronized older alternatives require a server relationship/persistence contract. Do not call invented answer-version methods or recreate a phone-only version database. See [Server chat relationships](SERVER_CHAT_RELATIONSHIPS.md).

Register a server-created child in the canonical chat resource before hydrating it. Hydration observes model controls through that owner; an unregistered child must never be passed to an owner-checked observer. The durable child stays reachable even when copy validation fails. `test/answer_versions_test.dart` and `test/saved_message_actions_test.dart` exercise the real fork, saved-boundary validation and continuation paths; static layout checks cannot establish this ordering.

After compaction, branch validation compares source and child saved REST history using `include_compacted=true`, raw roles/text and expected row counts. The shorter RPC display history is not an adequate copy boundary. If copied history is missing, changed or extra, retain the created child and report the failed validation explicitly rather than hiding the partial outcome.

## Attachments in history

Images use `image.attach_bytes` with filename, base64 content and session receipt. Generic files use `file.attach`; its returned `ref_text` precedes the visible question in the normal prompt. Reuse this contract for queue submission.

Saved user display removes generated expanded attachment context while preserving raw history and row identities. Restore missing references once, without expanding them again; assistant content is not subject to user-context stripping. An upload receipt proves staging, not that a model read the file. Automatic `@file` expansion can reject a staged path outside the workspace, matching the observed Desktop contract. Do not paste file bytes or rewrite the reference to conceal that backend boundary.

## Model, context and reading

Beside “Used N tools”, `1m 24s` shows the approximate interval from your saved
sent message to the final saved reply, using both Hermes timestamps. It includes
thinking and tool work and remains available after reopening Wing. Its tooltip
explains the calculation. Missing timestamps omit the time; it appears for a new
reply when saved history arrives. See [reply timing](TOOL_ACTIVITY.md#approximate-reply-time).

Messages show a discreet local `HH:mm` timestamp in the existing assistant
header or at the top of the user's side rail, with Edit and Copy at the bottom.
Long-press the time for its full date and local time; screen readers announce
the full value. All message action targets are 48 × 48 dp,
and the timestamp has its own
metadata space; adding a supplied time does not change the bubble geometry.
Copy still copies only the message.
Saved history uses the server timestamp. Newly submitted prompts and completed
reply segments use their local submission/receipt time until history refreshes.
Messages without a timestamp leave it blank; streaming replies gain their time
when the segment completes.

Choose models by the server's technical provider route and supported reasoning options. `/yolo` uses the current session's configuration and displays its returned state; it must not change global defaults.

The thin context ring beside the model selector uses server usage or a labelled estimate. Unknown is not zero. Warning thresholds are 65% and 85%. After cold resume, the lazy agent's ready event triggers a guarded `session.info`/breakdown refresh, without submitting a prompt or polling indefinitely.

Markdown, code and tables retain copying and horizontal overflow where appropriate. Long content supports bounded reading and return to latest. Find and tool progress are covered in [Execution and search](EXECUTION_FIND_AND_OUTPUTS.md); [output viewers](OPENING_OUTPUT_FILES.md) handle files. [Transcript projection](TRANSCRIPT_DISPLAY_TYPES.md) defines compact internal notices while preserving raw server history.
