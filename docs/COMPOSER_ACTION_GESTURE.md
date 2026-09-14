# Composer action gesture

Owner direction, 2026-09-14. This replaces the earlier W02 proposal that kept
Stop as the busy composer's primary action and opened a sheet on long press.

- A tap uses Steer while a turn is working. Hermes administration offers Steer,
  Queue, or Stop as the default for this device. Idle chats and slash commands
  use Send.
- Hold the button to open a vertical icon selector above it. Keep the finger
  down, slide to a choice, and release to run that action once. Holding in
  place keeps the primary action selected. Slide outside to cancel.
- The default sits at the bottom of the stack, closest to the button. Other choices are Stop, Queue, Fork, and
  Steer, with Send replacing Steer while idle. Selecting an alternative never
  changes the saved default.
- Unavailable choices stay visible and dimmed. Moving onto one shows why it
  cannot run. Releasing there does nothing. Empty text and attachments cannot
  be steered; Stop remains reachable through the gesture.
- Fork requires text and a completed saved answer. It branches at that answer
  and submits the draft in the child chat. It is unavailable during a turn.
- Pointer cancellation, navigation, app backgrounding, geometry changes, and
  changed action availability dismiss the selector without acting.
- Screen readers have named actions on the button, so dragging is optional.
  Queued-message rows still open queue management and support editing.

Tests cover held movement and release, cancellation, disabled choices, default
preference persistence, keyboard and large text layouts, screen reader actions,
accepted and rejected steering, queue attachment preservation, and fork delivery.
