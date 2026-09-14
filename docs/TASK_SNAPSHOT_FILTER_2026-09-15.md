# Task snapshot visibility

The reported bubble is the task list that Hermes injects into model context
after compression. It is not a new human prompt. The previous Android cleanup
covered process deliveries and `[System:` scaffolding but missed this envelope.

## Producer and Desktop check

Read-only audit of the installed Hermes source at
`498abb677ec39ea3ae9f8f5ed60e7def6bc47e70`:

- `tools/todo_tool.py`, `TODO_INJECTION_HEADER` and
  `TodoStore.format_for_injection`, define the stable header and task markers.
  Completed or cancelled parents can remain above active descendants. Task
  descriptions can contain multiple lines.
- `agent/conversation_compression.py`, `_fold_todo_snapshot`, appends standalone
  user-role rows with `_todo_snapshot_synthetic: true`. It can also append a
  snapshot to an existing real user message, or add a skill-reload instruction.
- `apps/desktop/src/lib/chat-messages/hydration.ts` has no task-snapshot branch.
  An executable audit bundled its actual `toChatMessages` implementation and
  confirmed that untyped reminders and reminders carrying the synthetic flag
  remain visible. `display_kind: hidden` hides them. The local audit and output
  are reproducible through the existing Desktop audit harness; this run's
  adapted script is in `build/task-snapshot-desktop-audit.cjs`.

This is source-based reproduction, not a capture of the phone server's response.
No backend or Desktop files were changed.

## Android rule

The shared `isHiddenAnswerMessage` projection honors `display_kind: hidden` and,
for user-role rows, the producer's boolean `_todo_snapshot_synthetic` flag.
For untyped rows it requires the exact task-snapshot header as the first line,
followed immediately by one of the producer's task markers and nonempty text.
The new fallback uses string comparisons, with CRLF normalization, and no regex.
It does not inspect task descriptions or status wording.

This removes standalone reminders from chat, search and saved-message editing.
Raw messages and durable row IDs and ordinals remain unchanged. Ordinary task
lists, assistant content, quoted reminders, partial headers and real messages
with an appended reminder remain visible. A supplied clean `display_content`
takes precedence for the untyped fallback.

An exact untyped copy of the complete producer envelope is indistinguishable
from the producer's own message. Consistent server display metadata would remove
that ambiguity. The fallback deliberately does not strip embedded text from a
real human message.

## Regression evidence

`test/task_snapshot_visibility_test.dart` first failed with one visible reminder
bubble where none was expected. It passed after the fix. It covers alternate
history encodings, CRLF, typed provenance, preserved raw history, ordinary lists
and quoted text. `test/internal_message_visibility_test.dart` checks restored
history, repeated refresh, search and absent edit controls for the same reminder.
The focused suite passed all 67 tests, and static analysis reported no issues.

The complete 2.36.12 suite passed 1,637 tests with 10 skipped. Output is in
`build/task-snapshot-full-tests.log` in the persistent build checkout.
