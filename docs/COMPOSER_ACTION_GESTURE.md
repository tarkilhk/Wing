# Composer action gesture

Owner direction, 2026-09-14. This replaces the earlier W02 proposal that kept
Stop as the busy composer's primary action and opened a sheet on long press.

- A tap uses Steer while a turn is working. App settings offers Steer,
  Queue, or Stop as the default for this device. Idle chats and slash commands
  use Send.
- The resting button always shows the up arrow. Holding animates it into the
  configured action, and sliding updates it to the highlighted choice. It
  returns to the arrow on release or cancellation. Reduced-motion settings
  switch icons immediately.
- Hold the button to open a vertical icon selector above it. Keep the finger
  down, slide to a choice, and release to run that action once. Holding in
  place keeps the primary action selected. Slide outside to cancel.
- The default sits at the bottom of the stack, closest to the button. Other choices are Stop, Queue, Fork, and
  Steer, with Send replacing Steer while idle. Selecting an alternative never
  changes the saved default.
- Unavailable choices stay visible and dimmed. Moving onto one shows why it
  cannot run. Releasing there does nothing. Empty text and attachments cannot
  be steered; Stop remains reachable through the gesture.
- Queue waits for the current send to finish submitting before moving the draft
  or attachments. The unavailable reason explains the wait; typing remains possible.
- Fork requires text and a completed saved answer. It branches at that answer
  and submits the draft in the child chat. It is unavailable during a turn.
- Pointer cancellation, navigation, app backgrounding, geometry changes, and
  changed action availability dismiss the selector without acting.
- Screen readers have named actions on the button, so dragging is optional.
  Queued-message rows still open queue management and support editing.

Tests cover held movement and release, cancellation, disabled choices, default
preference persistence, keyboard and large text layouts, screen reader actions,
accepted and rejected steering, queue attachment preservation, and fork delivery.

## Feedback


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
