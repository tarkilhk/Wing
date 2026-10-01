# Drafts and outgoing messages

Each conversation has one editable draft and an ordered outbox. These contain
unsent work, not copies of the conversation history.

- Editing an empty composer creates a draft. Clearing its text and attachments
  removes the draft portion of the saved record.
- Send saves the current text and attachments into the outbox before contacting
  Hermes, then clears the composer. The user can immediately start another draft.
- Offline Send keeps the message locally. After reconnecting and checking that
  conversation's state and history, known-waiting messages are sent in order,
  when the conversation is idle.
- A successful submission acknowledgement removes only that outbox item. New
  composer text and other outgoing messages remain. When no work remains, the
  conversation's saved record is removed.
- Before submission, the outgoing item is saved as uncertain. If acknowledgement
  is lost or the app exits during submission, it stays paused for review. Wing
  never automatically retries it. A deleted server conversation also keeps its
  unsent messages paused, without blocking other conversations.
- Send waits for an attachment being prepared. A failed initial save preserves
  the editable work and prevents network submission.

## Storage and performance

The `composer_work_v2` format uses one preferences entry per verified connection,
profile and conversation, with independently encoded identity components. Edits
serialize only that conversation. Writes to the same record are ordered across
stores sharing the preferences instance; unrelated records can progress
independently. Identical saves are skipped. The saved-draft browser uses a change
revision rather than comparing an aggregate JSON document on each notification.

This is a clean format change: old aggregate drafts and old string-only queue
entries are not read or converted. Existing old entries are not automatically
deleted. The user chose to clear old drafts before this change.

Preferences cannot atomically move two keys. A runtime replacement saves the
destination before removing the source; an interrupted transfer can leave two
recoverable copies. Platform write failures attempt to restore the previous
record. No storage implementation can promise durability after a failed write.

A local comparison with 40 unrelated 64 KiB drafts and ten small edits measured
the synchronous preparation of each save, excluding awaited platform completion:
the median fell from 7.212 ms to 0.032 ms, and each platform payload fell from
2,626,850 bytes to 138 bytes. This establishes less Dart-side serialization work,
not phone frame-time, native disk-write or battery improvement. Android's
preferences implementation may still rewrite its underlying file.

## Stock Hermes contract

Inspected upstream commit: `44a1ce9724502b9c692faaef00af3054bf11f1a6`.
The client uses stock `prompt.submit` with `session_id`, `text` and `queued: true`;
the flag prevents a busy-session race from steering an existing answer.
Acceptance is distinct from answer completion. The stock API provides no client
idempotency key, so neither matching history text nor a missing history row can
prove whether a lost-acknowledgement submission was accepted. Queued server
acceptance does not guarantee durability across a server crash.

References: [prompt contract](https://github.com/NousResearch/hermes-agent/blob/44a1ce9724502b9c692faaef00af3054bf11f1a6/tui_gateway/contracts/prompt_voice.py),
[submission implementation](https://github.com/NousResearch/hermes-agent/blob/44a1ce9724502b9c692faaef00af3054bf11f1a6/tui_gateway/methods_prompt.py).

## Verification

The focused tests are `composer_draft_record_work_test.dart`,
`conversation_outbox_lifecycle_test.dart` and
`conversation_outbox_screen_test.dart`, alongside the existing queue, attachment,
notification and recovery tests. They cover storage failures, overlapping saves,
offline/restart recovery, multiple submissions, lost acknowledgements, missing
conversations, attachment preparation and preservation of a fresh composer.
Rendered screens are checked at normal and 200% text sizes in both themes.
These host tests do not replace live Hermes and physical-device acceptance.
