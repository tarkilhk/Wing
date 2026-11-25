# Subagent supervision

While Hermes works, tap **Subagents** above your draft to inspect known children.
Only populated categories appear; swipe between Subagents, Tasks and Background when they
are available. The drawer keeps its summary visible while longer lists scroll.
Swipe up on the Subagents bar to open it at its compact height, then swipe up
again to maximize. Swipe anywhere in the drawer up to expand or down to close;
at full height, scroll rows back to their
top before continuing downward to close. Diagonal swipes follow their larger
component, switching categories when mostly sideways. The smaller top handle
toggles height on tap. Reopening by tap starts compact. Tap the selected tab,
outside or Back to close it without leaving the conversation.

The header shows completed out of total, then running and queued counts. Failed,
interrupted and unconfirmed agents are counted separately when present. Zero
status counts are omitted; unconfirmed agents are not also counted as running
or queued.

Received events update progress automatically. Reopening Subagents fetches a
fresh snapshot. If a read fails, use the Retry icon inside its error notice;
the icon shows progress until the attempt succeeds or fails. Past answers retain
**Activity → Agents** with received goals, status, output and available timings.
Historical results do not offer live controls.
Completed agents leave the drawer when their parent turn ends. Their saved
results stay under that answer's Activity, while unfinished background
agents remain in the drawer until they finish.

Open a child's details to read its own conversation through the parent chat. It uses the same message and Activity timeline as the main
chat, including saved tool results, available reasoning and live tool previews.
Expand **Task** for its goal and metadata. Eligible guidance and Send controls
stay below the conversation, with Interrupt in the status row. Nested read-only viewers do not offer those controls.

Use Refresh in the header to reread the child. Updates continue while the viewer is open and
Wing is active. After three consecutive failures, automatic refresh stops;
Refresh retries and resumes polling. Closing the sheet stops its reads. The parent chat and draft stay selected.

**Steer** appears when the child accepts guidance. Accepted guidance is queued,
so delivery can still be missed if the child finishes first. Failed or rejected
steering keeps your text. **Interrupt** confirms the interruption request, then
waits for the child to report its final state.

## Refresh and unavailable output

If a known child disappears from a refresh without a confirmed final state,
Wing marks it unconfirmed and disables controls. Later activity or another
refresh can confirm it again. Absence does not mean completion.

Received content remains visible when a later refresh fails. Live tool previews
may omit full arguments and results; saved receipts can provide those details.
Live tool completion can be inferred by Hermes when the next tool starts, so
Wing does not show an exact duration from that boundary.

The viewer reads the latest saved window and can load older pages. Refresh
rebuilds only the depth already loaded. Automatic updates keep the reading point
when it survives; if replacing the window would remove it, Wing keeps the old
window and reports newer activity. Use Refresh or Latest to continue. Explicit
Refresh returns to Latest when the old reading point is outside the new window.

A failed or changed multi-page read keeps the whole previous window. Unavailable
saved history clears that window and its file actions; independently received
live work remains. Empty saved history is a separate state. Files, images and
skill readers follow the child returned with the committed window, including
when Hermes moves work to a new continuation. Pending reads from the old child
cannot deliver into the new one. Finished children can still have readable saved
history even after leaving the live roster. This viewer does not grant controls
or provide a complete cross-session agent tree.

See [Tool activity](TOOL_ACTIVITY.md) for saved and live activity views.
