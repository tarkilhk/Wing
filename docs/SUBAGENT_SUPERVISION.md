# Subagent supervision

Open a chat's three-dot menu and choose **Subagents**, or open Activity's
**Agents** tab, to inspect its children. Received activity also shows a compact
expandable roster in the conversation. Saved delegation results show received
tasks, status, and output; they do not offer controls for past work.

Open a live child's details to read its goal, status, available activity, and
selectable output. Output refreshes every two seconds while the sheet is open
and Wing is active. After three consecutive failures, automatic refresh stops;
use Retry. Closing the sheet stops refreshing. Refresh the roster manually when
needed; received live events update known progress.

**Steer** appears when the child accepts guidance. Accepted guidance is queued,
so delivery can still be missed if the child finishes first. Failed or rejected
steering keeps your text. **Interrupt** confirms the interruption request, then
waits for the child to report its final state.

## Refresh and unavailable output

If a known child disappears from a refresh without a confirmed final state,
Wing marks it unconfirmed and disables controls. Later activity or another
refresh can confirm it again. Absence does not mean completion.

The detail sheet retains the last received transcript when a later read fails
or becomes unavailable. Recent tool and progress entries remain inspectable.
When no transcript is available, Wing says so and shows the activity it received.

Hermes' live list contains active children only, and live output is limited to
its final 16 KiB. Finished children can disappear and their output may no longer
be available. Received completion summaries remain with the current chat; saved
results depend on what Hermes recorded. Wing does not provide a complete
cross-session agent tree or archive of live child transcripts.

See [Tool activity](TOOL_ACTIVITY.md) for saved and live activity views.
