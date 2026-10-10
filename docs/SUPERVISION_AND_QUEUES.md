# Queues, Recents, and pending input

## Follow-up queue

Queue moves composer text and attachments into an unsent entry for that chat.
Attachment-only entries are supported; Steer accepts text only. The separate
composer draft remains available.

Hold a queued row to edit it in the composer. Queue saves the edit in its
original position. Steer sends the edited text into the active turn and removes
it after acknowledgement. Cancel restores your separate draft; deletion requires
confirmation. Back hides the keyboard first, then cancels editing. Sending the
queue pauses while an edit is open.

When connected, Wing sends one entry at a time after a completed turn. Restored
work waits for a server-state check. Stop, upload or send failure, and uncertain
delivery pause remaining entries for review and explicit resume. Restarting does
not automatically repeat uncertain work. Failed saves preserve queued work and
newer composer edits. See [Drafts and outbox](DRAFTS_OUTBOX.md).

## Recents

Recents includes chats with messages from the last 24 hours and ongoing work
across profiles on the selected connection. Opening a chat, creating an empty
chat, or editing a draft does not make it recent. All, Running, and Needs input
stay at the top; the latter two filter by live state.

Back returns to Recents with your filter retained. Chats opened from Chats return
to Chats. Within a chat opened from Recents, swipe horizontally with two fingers
to switch to an adjacent conversation. Pinch inward to open the circular card
stack; accessible icon controls and keyboard controls are also available. Back
closes the stack first.

Failed profile reads can leave coverage incomplete. Child-only work may be absent
when its parent is idle; open [Subagents](SUBAGENT_SUPERVISION.md) to check a known
parent's children. See [Chats](CHATS.md).

## Sensitive input, approvals, and questions

Sudo passwords, environment secrets, vault unlocks, saved logins, and verification
codes use dedicated forms. Enter them there rather than in the composer. Typed
credentials stay in memory and are not saved in drafts or conversation messages;
after reconnecting, an outstanding form may return but its typed secret does not.
Withdrawn or expired requests close without being treated as a denial.

Approvals show the requested operation and the scopes Hermes offers, such as
Deny, Allow once, Session, and Always. Questions can contain multiple items and
retain confirmed answers. Requests belong to their original chat and profile.
Check the displayed outcome when a response cannot be confirmed.

## Side questions

`/btw`, `/bg`, and `/background` show the submitted question and any received
result. Empty results are labelled explicitly. These cards are temporary; a cold
restart may not recover the question or its linked result, and cancellation is
not available through these cards.

[Session controls](SESSION_CONTROLS.md) covers goals, loops, and processes.
[Notifications](BACKGROUND_NOTIFICATIONS.md) explains delivery and its limits.
