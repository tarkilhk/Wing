# Drafts and outgoing messages

Each conversation has one editable draft and an ordered outbox of unsent messages.

Typing or adding attachments creates a draft. Clearing both removes it. Send saves the current text and attachments into the outbox before contacting Hermes, then clears the composer so you can start another draft. Sending waits for an attachment still being prepared; a failed initial save keeps the editable work and prevents submission.

Offline Send keeps the message on this device. After reconnecting and checking the conversation, messages known to be waiting are sent in order when the chat is idle. Acknowledgement removes only the accepted item; it does not clear newer composer text or other outgoing messages. Acceptance means Hermes received the request, rather than that its answer is finished.

## Uncertain delivery

If acknowledgement is lost or Wing closes during submission, the item stays paused for review. Wing never automatically resends it. Check the server conversation, then edit or remove the uncertain item before continuing. Matching text in history, or its absence, cannot conclusively establish whether Hermes accepted a lost-response send.

A deleted server conversation keeps its unsent work paused without blocking other conversations. Recovering a draft to another conversation may leave two recoverable copies if interrupted; review them before sending.

## Saved-message actions

Edit and Restore preserve your separate draft and pause outgoing follow-ups for review. Regenerate and Branch use the chosen saved answer. See [Conversation actions](CONVERSATION_ACTIONS_AND_READING.md) and [Queues and pending input](SUPERVISION_AND_QUEUES.md).

Drafts and the outbox are device-local and are not included in configuration backups. A failed device-storage write cannot guarantee that the latest edit was saved.
