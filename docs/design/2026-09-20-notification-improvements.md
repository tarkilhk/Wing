# Notification improvements — agreed requirements

Date: 20 September 2026. Status: **implemented and verified in the workspace; not released**.

This document consolidates the notification study and subsequent decisions in
the conversation. The user initially requested a read-only study, then approved
isolated visual prototypes and this record. It is not a claim that the proposed
behavior has shipped. The emulator previews used a separate application with
sample data and no connection to Hermes.

The user subsequently authorized implementation. This remains the agreed specification. Where it differs
from [the earlier rich-notification plan](../../plans/001-rich-chat-notifications.md),
this document takes precedence: notably one notification per chat, notification
actions, richer state-specific content, and the new monitoring icon.
[Background notifications](../BACKGROUND_NOTIFICATIONS.md) now describes the implemented operation.

## 1. Purpose

At a glance, a notification should tell the user:

- Which chat it concerns.
- What actually happened or is happening.
- What they should do next: read the answer, answer a question, review an
  approval, or inspect a failure.

Use as little static text as possible. Maximize useful, event-specific
information instead of filling the notification with generic messages such as
“Needs your attention”, “Finished working”, or “Open the chat for details”. A
completed reply still has a next step: the user needs to read it.

The problems to address are stale or competing notifications, insufficiently
informative copy, missing approval actions, weak visual differentiation, and a
static monitoring notification that says little about the work being watched.

## 2. Channels, preferences, and behavior to retain

Use Android notification channels to distinguish actionable attention, ordinary
updates, and ongoing monitoring. Preserve user control through Android's channel
settings and Wing's notification preferences. Existing channel separation should
be reused where it already provides the agreed behavior.

- Attention/input requests warrant the attention channel and its higher default
  importance; ordinary results use the updates channel.
- The user wants every chat notification to request sound, including queued
  approvals, rather than suppressing sound after the first request. Android's
  user-controlled channel, device, and interruption settings remain authoritative.
  Sound applies to new answers, newly arriving requests, and advancement to the
  next pending request. Monitoring refreshes, unchanged-state redraws, and
  transient submission-status updates stay quiet. Keep this policy simple;
  revisit only if real use proves too noisy.
- Monitoring is ongoing, low importance, and quiet. Routine content refreshes
  should not repeatedly alert the user.
- Notification diagnostics/settings should distinguish app-wide permission from
  an individually blocked channel and provide a useful route to the relevant
  Android setting. A successful test notification is not proof that every
  channel or server event works.

The following choices explicitly remain as they are today:

- **Permission timing:** keep the existing startup notification-permission flow;
  do not move it to a later contextual prompt.
- **Foreground attention behavior:** approvals/attention may alert even when
  their chat is visible. Keep existing completion suppression for the visible
  chat; do not apply blanket foreground suppression to attention.
- **Posting retry behavior:** no new notification-posting retry system is part
  of this redesign. This does not remove existing connection recovery or the
  reconciliation needed to keep notifications current.

Keep existing preview privacy controls and Android lock-screen visibility.
Turning previews off must also hide rich custom-notification content. Do not
expose secure-input values or turn internal exceptions into notification copy.

## 3. One latest relevant notification per chat

Maintain **one visible chat notification per connection/profile/chat identity**.
“Latest” means the latest state relevant to the user, not simply the last event
received. Chats with identical titles must remain independent.

Priority and transition rules:

1. **Unresolved input takes priority.** A newer result must not replace an
   unanswered approval or question.
2. **Represent the current request and its queue.** Show what needs a decision
   now and how many requests remain. Update the same notification as the queue
   changes rather than creating one notification for every request. Across
   approvals, questions, and secure input, use FIFO: retain the oldest unresolved
   input known to Wing as the displayed request until it resolves.
3. **Advance when resolved.** A local decision, decision from another client,
   cancellation, or expiry removes that request from the notification state.
   Show the next unresolved request if one exists.
4. **Then show the latest unread result.** Once input is resolved, show the latest
   unread relevant result, or clear the notification if nothing remains.
   Starting another turn alone does not erase the previous unread answer; retain
   it until a newer answer replaces it or it is read/dismissed, subject to the
   already agreed precedence of pending input.
5. **Clear what the user has read.** Reading the relevant result clears its
   notification. Merely opening Wing must not clear unrelated chats or requests.
   Reaching the particular latest answer is sufficient; reading every line is
   not required. Existing transcript visibility measurements make the user's
   preferred answer-specific rule feasible. Do not substitute bottom-of-chat:
   newer activity below an answer can put the bottom on screen without that
   answer ever becoming visible. Tie the read acknowledgment to the exact result
   represented by the notification so it cannot clear a newer replacement.
   For this revamp, read-based clearing is local to actual answer visibility in
   Wing. Do not add a manual Mark read / Mark unread workflow or use desktop
   opening as proof of reading the particular answer. This does not prevent
   synchronization of requests completed on desktop.
   **Accepted stock-Hermes limitation (option 2):** main answer completion events
   have no stable message ID. In that case, tapping opens the latest available
   assistant reply in the owning chat, and seeing that reply clears the matching
   notification revision. Do not copy answers into the transcript or infer IDs
   by matching prose. If history has advanced, this may open a newer answer;
   this practical limitation was explicitly accepted. Stable request/task IDs
   still select their corresponding request/result.
6. **Respect dismissal.** Swiping away a notification performs no backend action.
   A routine refresh must not resurrect the same dismissed alert; genuinely new
   relevant state may warrant a new alert. A newly arriving approval does bring
   back a dismissed notification even if an older approval remains unresolved.

Reconcile notification state with current authoritative chat/request state,
including reconnect and decisions made on desktop. Clear stale notifications
automatically. Connectivity loss or a failed read is not evidence of completion,
resolution, or success. Retain silent initial/reconnect baselines rather than
re-alerting historical events.

All taps and actions retain the owning connection, profile, chat, and, where
applicable, exact request identity. A stale action must never act on the next
request just because it occupies the same notification slot.

Tapping the notification body opens the corresponding chat **at the represented
answer or input request**, so the user can review it. Review actions use the same
destination. Simply entering the chat is not sufficient if the target remains
off screen. Opening failures do not satisfy the read/resolution condition.
If the original target is no longer available, open the owning chat with its
current state; do not silently substitute the next request as the target of an
approval action. Targeted scrolling is new client work: today's payload only
contains chat identity.

For mixed pending input, count remaining user decisions by kind, for example
**2 approvals · 3 questions**, rather than counting a three-question form as one
decision. Keep FIFO request order while advancing the questions within a form.

## 4. Useful content from official Hermes data

Prefer official structured Hermes events and fields. Do **not** infer state,
approval scope, outcomes, or next steps by parsing model-generated prose or
text wrappers whose wording can change between Hermes releases. Formatting a
known display field for readability is separate from inventing a wire contract
from its text.

| Situation | Useful content and next step |
| --- | --- |
| Reply/result available | Actual answer or result excerpt; tap to read the owning chat. Side/background results use their own content and do not imply the parent task finished. |
| Question | Actual question and supported choices, where provided; open the chat to answer when no suitable notification action is supported. |
| Approval | Backend-provided redacted command, useful description/tool context, pending count, and the supported approval choices. |
| Secure input | Indicate the required input and open the secure in-app flow; never include the secret itself. |
| Failure/interruption | Show a useful structured reason when available and make the next step clear. Do not invent a reason or claim success. |
| Status-only event | Use the most specific factual state available. A short static message is acceptable when the backend supplies no useful content. |

Retain chat identity as the primary context and connection/profile as subordinate
context. Expanded notifications expose more of the useful content. Do not borrow
an old assistant answer to populate a new event with missing content. Avoid
repeating a long fixed instruction when the answer, command, or question would
use that space better.

Backend limitations should remain visible as limitations. This work does not
authorize backend changes, a new model-generated summarization service, or
guesses about unsupported structured fields.

## 5. Approval actions, including queues

Show **all choices offered for the individual request** directly in the expanded
notification, using compact controls:

**✓ Once · ✓ Session · ✓ Always… · ✕ Deny**

- The ticks are action icons, not checkboxes or persistent selections.
- Use a red cross for denial where the notification theme permits, and retain
  the **Deny** label so it cannot be confused with dismissing the notification.
- Do not show an unsupported scope or manufacture choices absent from the stock
  request contract.
- **Once** answers the displayed request once.
- **Session** grants the backend's session-scoped permission. This concerns the
  matching command pattern; it is not “approve every queued request”.
- **Always…** opens a confirmation for the permanent command-pattern rule,
  matching desktop semantics. The ellipsis signals that further step. Permanent
  permission must not silently be granted from an ambiguous one-tap action.
- **Deny** rejects the displayed request; it does not clear or reject the entire
  queue.
- With message previews disabled, replace direct permission choices with
  **Review**, opening the corresponding Wing chat for the decision.
- Require device unlock before any approval or denial is submitted. The custom
  action path must enforce this explicitly; private lock-screen content alone
  does not constitute an action authentication policy.
- If the full command cannot fit in the notification, retain the supported
  choice controls but open the owning chat to review the complete command and
  confirm the selected scope before submitting. Short commands retain direct
  actions. Tapping the notification body also goes to the represented request.

The queue count and displayed command must refer to the same current request.
After a successful response, refresh authoritative pending state and update the
same notification. Backend coalescing can resolve multiple matching entries, so
do not simply subtract one from a local counter. Repeated taps, delayed replies,
expiry, and another client's decision must not approve a different request or
report an unsuccessful submission as successful.

Keep the notification while a decision is being submitted and prevent duplicate
submission. After Hermes confirms acceptance, advance to the next pending input
or show the latest unread result/clear as appropriate. Acceptance means the
decision was accepted, not that the approved command finished successfully.
On failure or an unconfirmed response, retain truthful status, reconcile the
request, and allow an explicit retry if it remains pending. Never automatically
send a permission grant later when connectivity returns. Expiry, cancellation,
and a decision made on desktop still clear stale requests. Normal user dismissal
remains possible; it performs no server action.

### Custom Android presentation

The user approved a **custom notification** so all four actions can be visible;
the standard Android action row supports at most three. Use an Android-decorated
custom expanded layout (`RemoteViews` with `DecoratedCustomViewStyle`), retaining
the system notification header and normal expansion behavior.

- Normal text: one compact row of the supported choices.
- Enlarged text: a 2 × 2 arrangement when all four choices are present, preserving
  readable labels and reachable controls.
- Collapsed form still identifies the chat, request, and useful context; the
  expanded form exposes the full choice set.
- Check both light and dark themes, large text, accessibility labels, and
  Android's custom-content height constraints. Color must not be the only cue.

Saved layout evidence:

- [Four actions, normal text/light](images/notifications-2026-09-20/approval-actions-light.png).
- [Four actions, large text/dark](images/notifications-2026-09-20/approval-actions-dark-large.png).

These are native rendering prototypes with sample content, not working backend
actions. Their monitoring icon predates the final icon alignment; use the icon
artifacts in section 8 for the approved monitoring design.

## 6. Stock Hermes approval contract recorded during the study

The notification study inspected upstream commit
`490e6b5966de330285905f52ebaee23c842dc3ea`. This is the research snapshot, not a
version pin. Before implementation, reverify **latest upstream, unmodified
Hermes** and record the inspected commit, as required by
[AGENTS.md](../../AGENTS.md). The separate
[command-approval work](2026-09-20-command-approvals.md) also documents existing
client integration and verification.

Findings to preserve in the implementation:

- Official choices are `once`, `session`, `always`, and `deny`.
- `smart_denied` limits the offered approval scopes to once/deny;
  `allow_session: false` excludes session and always;
  `allow_permanent: false` excludes always. Respect each request's actual choices
  and constraints.
- Desktop exposes Run/Reject plus session/permanent options, and separately
  confirms a permanent command-pattern permission.
- Preserve the distinction between the live server-request envelope ID and the
  approval queue entry's `request_id`. Use the identity required by the selected
  stock response operation, never an implicit oldest/all-requests target.
- `request.answer` serves live server requests; `approval.respond` serves the
  queue response path. Both are current stock operations, not legacy fallbacks.
- `approval.respond` returns `resolved`; zero means no request was resolved.
  `request.answer` reports success/expiry. Interpret the actual result before
  advancing presentation.
- Reconcile with `approval.pending`; handle `request.cancel` and expiry. The
  pending-list representation can carry permission flags without the live
  request's normalized choices.
- Use structured fields such as the redacted command, description, choices,
  flags, and optional tool name. A description of a matching approval pattern
  is not necessarily a summary of the user's task.

References at the inspected commit:

- [Gateway request construction](https://github.com/NousResearch/hermes-agent/blob/490e6b5966de330285905f52ebaee23c842dc3ea/tui_gateway/server.py).
- [Server-request contracts](https://github.com/NousResearch/hermes-agent/blob/490e6b5966de330285905f52ebaee23c842dc3ea/tui_gateway/contracts/server_requests.py).
- [Response and pending methods](https://github.com/NousResearch/hermes-agent/blob/490e6b5966de330285905f52ebaee23c842dc3ea/tui_gateway/methods_prompt.py).
- [Desktop approval UI](https://github.com/NousResearch/hermes-agent/blob/490e6b5966de330285905f52ebaee23c842dc3ea/apps/desktop/src/components/assistant-ui/tool/approval.tsx).
- [Approval waiting/queue behavior](https://github.com/NousResearch/hermes-agent/blob/490e6b5966de330285905f52ebaee23c842dc3ea/tools/approval_gateway_wait.py).
- [Approval scope semantics](https://github.com/NousResearch/hermes-agent/blob/490e6b5966de330285905f52ebaee23c842dc3ea/tools/approval.py).

All implementation is client-side. No backend patches, forks, plugins, custom
endpoints, server upgrade, or backward-compatibility layer is authorized by this
design.

### Follow-up: desktop completion and synchronization

Further stock verification at `efa09f49c12fd05a991ffa972a6b0419ea104988` found that
normal successful answers do **not** universally emit `request.cancel`. That
event covers cancellation/expiry paths; do not rely on it as the only evidence
of a decision made on desktop. Session events can also be routed to the owning
transport rather than broadcast to every attached client.

Stock `session.events.since` includes current `open_requests`, and
`approval.pending` provides the approval queue. Wing can reconcile those
authoritative, correctly scoped snapshots to clear resolved input or advance
the notification, including partially answered question forms. Global
`sessions.changed` can trigger a check, but it is not a guaranteed signal for
each successful request response. While requests remain pending, periodic
reconciliation is needed if timely desktop cleanup is expected without a
guaranteed push event.

Periodic reconciliation runs **only while the existing monitoring watcher is
already running**. The user rejected extending its lifetime for pending input:
notifications must neither start nor keep monitoring alive just for cleanup.
Use the existing runtime/connection, restrict checks to notification-relevant
chats, coalesce overlapping triggers, and avoid concurrent polling loops or
retry churn while offline. No separate always-on worker or wake-up mechanism.

When monitoring stops, periodic notification cleanup stops with it. Reconcile
current state when the normal runtime reconnects/resumes; stale notifications
can remain in the meantime. Backend updates cannot wake a stopped Wing process
and directly cancel an Android notification under the existing design.

Desktop opening/reading is separate. The user permits remote read-based clearing
only if the marker means the last chat message was read. Verification at stock
commit `b7d7d2929a10e0658a98a7a03f4531093e1480ed` shows that condition is **not met**:
desktop marks the selected chat read without checking message visibility, and
the backend records its own time when the read mutation is processed. A newly
arrived message can therefore fall under that watermark without desktop having
displayed it. Comparing the watermark against the notified message timestamp
does not establish that the message was seen.

Consequently, do not clear result notifications from the stock desktop read flag
or timestamp. Keep actual-answer read detection Wing-local. Reconcile remote
request completion/cancellation/expiry while the existing watcher runs; those
are meaningful state changes independently of any read flag. Missing or failed
snapshot responses are not evidence of resolution.

Primary sources:

- [Request resolution/cancellation](https://github.com/NousResearch/hermes-agent/blob/efa09f49c12fd05a991ffa972a6b0419ea104988/tui_gateway/server_requests.py#L201).
- [Current open requests with event replay](https://github.com/NousResearch/hermes-agent/blob/efa09f49c12fd05a991ffa972a6b0419ea104988/tui_gateway/methods_session.py#L2246).
- [Session and global routing](https://github.com/NousResearch/hermes-agent/blob/efa09f49c12fd05a991ffa972a6b0419ea104988/tui_gateway/server.py#L623).
- [Desktop read handling](https://github.com/NousResearch/hermes-agent/blob/b7d7d2929a10e0658a98a7a03f4531093e1480ed/apps/desktop/src/store/session-unread-remote.ts).
- [Backend read watermark](https://github.com/NousResearch/hermes-agent/blob/b7d7d2929a10e0658a98a7a03f4531093e1480ed/hermes_state_sessions.py).

## 7. Distinct visual cues by notification type

Make updates, requests for input/approval, stopped/failed work, and ongoing
monitoring distinguishable at a glance. Use type-specific small-icon cues and
clear content, supplemented by notification styling where Android permits.

The Android **small notification icon** is the relevant asset: it appears both
in the status bar and in the notification header. This is not a redesign of
Wing's launcher icon. Preserve Wing identity across the notification family;
do not rely on color alone, since status-bar icons are monochrome/tinted by
Android.

The requirement for type differentiation is agreed. Only the monitoring icon's
exact artwork was selected in this conversation; the other type glyphs should
follow that requirement without treating unreviewed artwork as approved.

## 8. Approved monitoring icon

Replace the caduceus with **the original full-size wing over a circular pair of
arrows**. The wing keeps its normal notification size and shape; the arrows sit
behind it rather than requiring the wing to shrink.

The final selection is the **softer-tone circle, centered on the wing's center
of mass**. Earlier faint-circle, smaller-wing, signal-arc, and fully opaque
circle alternatives are not the selected design.

The preserved vector is the source of truth:

- [Approved Android vector](images/notifications-2026-09-20/monitoring-approved.xml).
- [Actual Android 16 emulator, dark background](images/notifications-2026-09-20/monitoring-approved-dark.png).
- [Actual Android 16 emulator, light background](images/notifications-2026-09-20/monitoring-approved-light.png).

It uses a 24 × 24 viewport, the untransformed existing wing, a stronger 1.9-unit
arrow-circle stroke, and 0.82 opacity for the softer arrows. Arrowheads sit away
from the wing tips. The circle is translated approximately 0.239 units left and
1.453 units down so its center matches the wing's filled-area centroid, about
(11.761, 13.453). The user accepted this final alignment after viewing the actual
status-bar rendering. Do not substitute the earlier, higher circle placement.

These assets are documentation references, not production resources installed by
this documentation change.

## 9. Informative ongoing monitoring

Replace static monitoring text with a current summary of the actual work, for
example:

> Watching 3 chats
>
> 2 working · 1 needs approval

Counts and state descriptions must update as work and requests change. Use
known application state, not guessed task summaries. Represent a connection or
recovery problem truthfully instead of implying that events are being observed
when they are not.

Retain the existing automatic monitoring lifecycle, separate monitoring group,
and general app-opening destination. The summary describes the chats actually
covered by the current runtime; it must not claim to watch every saved server.
This design improves information, not the server's delivery guarantees or the
ability to wake a stopped process.

## 10. Verification

The agreed behavior implies the following acceptance checks:

- One visible alert per scoped chat; identical titles across profiles do not
  collide. Pending input survives a newer reply.
- Multiple approvals show accurate current-request content and queue count;
  once/session/always/deny appear only when supported. Permanent scope confirms
  the actual pattern. A stale action cannot answer the next request.
- Local and remote decisions, expiry, cancellation, reconnection, and coalesced
  resolutions refresh or clear the correct notification without false success.
- Reading clears the relevant result; opening the app does not clear unrelated
  state; dismissal neither answers nor routinely resurrects the same alert.
- Content comes from the relevant structured event. Missing fields produce
  factual copy; no prose parsing, unrelated old reply, or sensitive-value leak.
- Permission timing, foreground attention, completion suppression, notification
  preferences, and existing posting retry behavior remain as agreed.
- Monitoring copy tracks live counts/state, and its approved wing/circle renders
  correctly at real status-bar size on light and dark backgrounds.
- Native notification inspection covers collapsed/expanded states, all offered
  actions, large text, lock-screen privacy, and channel-specific disablement.

The original saved previews verify selected rendering choices only. Production
controller tests and the isolated native QA fixture provide separate interaction
evidence; see the implementation record below.

## Design interview follow-up

The [design interview](2026-09-20-notification-design-interview.md) records the
follow-up answers and remaining questions. Accepted answers are incorporated
above. In particular, the user rejected silent approval-queue progression,
accepted FIFO across input types, chose Review when previews are hidden, and
required device unlock. Round 2 settled sound boundaries, confirmation-based
approval clearing, long-command review, per-decision counts, no manual read
workflow, and answer-specific tap destinations. Round 3 retained the existing
watcher lifetime and limited polling to it. Stock desktop read markers do not
meet the user's last-message-read condition, so they are excluded from cleanup.
The user confirmed the behavior and explicitly authorized implementation. The
final follow-up selected option 2: open the latest available reply when Hermes
does not supply a stable answer message ID.

## Implementation and verification record

The revamp is implemented entirely in Wing. Stock Hermes was inspected at
`b7d7d2929a10e0658a98a7a03f4531093e1480ed`; no backend or desktop code was changed.
Notification state, FIFO order and dismissals persist locally. Pending actions use
exact request IDs and require stock `request.answer: status=ok` or
`approval.respond: resolved>0` acceptance. Reconciliation uses one active-session
snapshot per controller and remembers replay cursors; a single 30-second timer
runs only with the existing watcher, with an additional normal-resume check.

Validation on 20 September 2026:

- Full Flutter suite: **2,658 passed, 12 skipped**, including the final
  navigation/failure refinements, expired acknowledgments,
  request-specific errors, restored read targets and the accepted option 2.
- Static analysis: no issues. Release-tool unit tests: **28 passed**.
- Production-entry debug and signed ARM64 release APK builds. Build 2323
  (`1.0.1`, ARM64 versionCode `23232`) verified for the production package,
  non-debuggable status, architecture and pinned release signing certificate.
- Actual Android 16/API 36 emulator, isolated `com.tarkilhk.wing.notificationqa`
  package, fake Hermes transport through production WingApp/controllers/native
  notification code: exact-head Once, FIFO advancement, failure retention,
  Always confirmation/cancel, hidden-preview Review, watcher-driven remote
  resolution, and latest-reply tapping/clearing without clearing another chat.
- Secure-lock-screen check: commands and direct choices are hidden; no approval
  is submitted while locked. The temporary emulator PIN was removed afterward.
- Actual rendering inspected in light/dark at 100% and 200%. Large text uses
  fully visible two-row controls. Existing notices redraw quietly on live
  Android font/theme changes. These checks exposed and fixed stale activity
  configuration and lazy transcript navigation timing issues.

Actual implementation screenshots:

- [Light / normal](images/notifications-2026-09-20/implemented-light.png)
- [Dark / normal](images/notifications-2026-09-20/implemented-dark.png)
- [Light / 200%](images/notifications-2026-09-20/implemented-large-light.png)
- [Dark / 200%](images/notifications-2026-09-20/implemented-large-dark.png)
- [Reply](images/notifications-2026-09-20/implemented-reply.png)
- [Stopped work](images/notifications-2026-09-20/implemented-stopped.png)

The input exclamation/wing and stopped square/wing are implementation proposals
for the agreed type distinction, not a claim of prior approval of their exact
artwork. Monitoring uses the exact approved wing/circle vector. The emulator's
Wing Dev label and synthetic chat content belong to the isolated QA build.

The device checks do not certify every manufacturer's notification UI. Main
answers without IDs intentionally target the latest available reply. Desktop
read markers remain excluded because their semantics fail the user's condition.
When the watcher stops, background cleanup pauses until normal resume/reconnect.

Use the [one-chat live test prompt](2026-09-20-notification-live-test-prompt.md)
for the remaining real-Hermes/device checks. The synthetic emulator checks do
not establish that every scenario can be generated by an installed backend.

## Android reference material

- [Notification anatomy and behavior](https://developer.android.com/develop/ui/views/notifications).
- [Notification channels](https://developer.android.com/develop/ui/views/notifications/channels).
- [Custom notification layouts](https://developer.android.com/develop/ui/views/notifications/custom-notification).
- [Notification creation and actions](https://developer.android.com/develop/ui/views/notifications/build-notification).
