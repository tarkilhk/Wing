# Composer feedback

Queued prompts stay outside the scrolling transcript, directly above the
composer. Each entry shows a return arrow and small italic text, including
attachment names. The list has a bounded height and scrolls when needed. Tapping
an entry opens the existing queue actions. Saving and paused states are visible.
Entries disappear when sent or removed; a failed save restores the draft.

Accepted steering appears immediately in the transcript as a compact compass
row: `steered · <message>`. Rejection or connection failure keeps the draft and
shows the existing error. Typing another draft while acceptance is pending does
not clear the new text.

Saved `display_kind: steer` rows use the same presentation. Complete standalone
user steering envelopes lose their `OUT-OF-BAND USER MESSAGE` wrapper only in
display. Raw history remains intact. Quoted, incomplete and assistant markers
remain visible.

The local Hermes Desktop reference uses the compact compass row in
`apps/desktop/src/components/assistant-ui/thread/system-message.tsx` for tool
steering. Its newer `redirectPrompt` action uses a different RPC and normal user
messages. This change retains Android's existing `session.steer` behavior.

Regression checks cover delayed acceptance, rejection, transport failure, newer
drafts, history hydration, queued attachments and large text sizes.
