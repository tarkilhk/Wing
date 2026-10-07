# Composer action gesture

Owner direction, 2026-09-14. This replaces the earlier W02 proposal that kept
Stop as the busy composer's primary action and opened a sheet on long press.
The 8 October refinement below supersedes the always-arrow resting state for
an empty composer while a turn is working.

- While a connected turn is working and there is no draft text or attachment,
  the button shows Stop and a tap interrupts that turn. No held column or
  alternative keyboard/screen-reader actions are offered in this state. This
  includes submission before the first reply arrives. Completion returns the
  button to Send.
- The first typed character (including whitespace), or a draft attachment,
  restores the resting up arrow and configured column order. A tap uses Steer
  for a running draft by default. App settings offers Steer,
  Queue, or Stop as the default for this device. Idle chats and slash commands
  use Send. The automatic empty-composer Stop does not change this preference.
- The arrow lifts away as Stop settles into place; typing reverses the motion
  with a small settling bounce over 220 ms. Holding animates the button into the
  configured action, and sliding updates it to the highlighted choice. It
  returns to its current resting icon on release or cancellation. The held
  column unfolds upward with staggered 160–250 ms icon reveals. Reduced-motion
  settings switch icons immediately and omit the column entrance animation.
- Use the outlined compass (`Icons.explore_outlined`) for every steering icon,
  including composer actions, settings, queue controls and transcript feedback.
- Hold the arrow button to open a vertical icon selector above it. Keep the finger
  down, slide to a choice, and release to run that action once. Holding in
  place keeps the primary action selected. Slide outside to cancel.
- The default sits at the bottom of the stack, closest to the button. With
  Steer as the default, sliding upward visits Steer, Queue, Fork, then Stop.
  Send replaces Steer while idle. Selecting an alternative never changes the
  saved default.
- Unavailable choices stay visible and dimmed. Moving onto one shows why it
  cannot run. Releasing there does nothing. Attachment-only drafts cannot
  be steered; Stop remains reachable through the gesture for drafts, and as a
  direct tap when the running composer is empty.
- Queue waits for the current send to finish submitting before moving the draft
  or attachments. The unavailable reason explains the wait; typing remains possible.
- Fork requires text and a completed saved answer. It branches at that answer
  and submits the draft in the child chat. It is unavailable during a turn.
- Pointer cancellation, navigation, app backgrounding, geometry changes, and
  changed action availability dismiss the selector without acting.
- Screen readers have named actions on the button, so dragging is optional.
  Queued-message rows still open queue management and support editing.
- Hardware keyboards can Tab to the action button whenever any action is
  available. Enter or Space runs an available primary action; when the primary
  is unavailable, either key opens the action menu. Down arrow, the Menu key and
  Shift+F10 open the menu directly. Arrow keys select an available action, Enter
  runs it, and Escape closes the menu and returns focus to the button.

ComposerSession publishes the empty-running-composer decision in
`ComposerActions.prefersStopAction`; the view only projects that decision and
the saved running action into button presentation. Dispatch and eligibility
remain with the existing owners. The stock `prompt.submit`, `session.interrupt`
and `session.steer` handlers were inspected at upstream main
[`ad12263a5ed43109d3942a8af04d4cef210fa6ae`](https://github.com/NousResearch/hermes-agent/tree/ad12263a5ed43109d3942a8af04d4cef210fa6ae),
in `tui_gateway/methods_prompt.py` and
`tui_gateway/methods_session_interrupt.py`. This refinement changes only the
Android client.

Tests cover held movement and release, cancellation, disabled choices, default
preference persistence, keyboard and large text layouts, screen reader actions,
accepted and rejected steering, queue attachment preservation, and fork delivery.
`test/composer_action_button_test.dart` covers both animated and reduced-motion
Stop/typing transitions, the Stop-only state, restored column order and
cancellation when the resting state changes.
`test/profile_composer_actions_test.dart` covers actual send-to-stop
dispatch, first-character restoration, completion and saved defaults in both
Studio themes at 100% and 200% text, including opt-in rendered captures.

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
