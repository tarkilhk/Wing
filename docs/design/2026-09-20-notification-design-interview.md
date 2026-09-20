# Notification design interview

Status: behavior decisions resolved; awaiting final confirmation of shared
understanding before implementation. This supplements the
[agreed requirements](2026-09-20-notification-improvements.md); recommendations
are labeled separately from accepted answers.

The interview uses grill-with-docs, grilling, and domain-modeling. Existing
decisions are retained. Implementation follows completion of the interview and
the user's confirmation of shared understanding.

## Design tree

- Current state rather than event history — settled.
  - One notification per scoped chat; unresolved input wins — settled.
  - Reaching the notified latest answer clears it — accepted, Q4.
    - Target-answer visibility is feasible and selected; bottom proxy rejected
      as unnecessary after code inspection.
    - No manual mark-read/unread workflow — Q12 rejected.
    - Opening failure does not clear an unread result — consequence of Q4/Q11.
    - Retain dismissal/read state across refresh/restart — lifecycle requirement.
    - Remote read-based clearing permitted only if stock read means the last
      message was read — stock fails that condition, so exclude it.
    - Desktop request completion clears through authoritative reconciliation —
      supported by stock snapshots, not guaranteed per-decision push.
    - Poll only while monitoring watcher already runs; never prolong it for
      pending notifications — accepted, Q15.
  - Multiple kinds of input use FIFO — accepted, Q5.
    - Count remaining decisions by kind — accepted, Q13.
  - Retain unread result when new work starts — accepted, Q1.
  - New approval restores dismissed notification — accepted, Q2.
  - Every notification should sound; silent queue progression rejected — Q3.
    - Routine redraws/monitoring remain quiet — accepted, Q9.
- Useful content from official structured data — settled.
  - Previews hidden: Review opens owning chat — accepted, Q6.
  - Truncated commands require in-chat review/confirmation — accepted, Q11.
  - Notification body opens at the represented answer/request — accepted, Q11.
- Direct approval actions with all supported scopes — settled.
  - Permanent-pattern confirmation — settled.
  - Require unlock for every approval/denial — accepted, Q7.
  - Retain notification until decision accepted or request otherwise resolved — Q10.
    - Failed/uncertain response: reconcile, explicit retry, no deferred grant — Q10.
    - Recovery must retain the exact target, verify current state, and preserve
      the accepted no-deferred-grant rule; opening alone does not clear a notice.
- Type differentiation and informative monitoring — settled.
  - Monitoring artwork and alignment — settled; preserve approved vector.
  - Remaining type artwork — implementation work within the agreed Wing identity
    and type-differentiation requirements; native visual verification required.
- Channels, permission timing, foreground attention, posting retry behavior — settled.

## Round 1 — answers recorded

### Q1. An unread result when another turn starts

Scenario: a result notification is still unread on the phone; another turn starts
in the same chat from desktop. Should the earlier result remain visible?

Recommendation: retain it until it is read, dismissed, or superseded by new
input/a newer result. Starting work alone does not prove that the phone's result
was read; ongoing activity belongs in the monitoring notification.

**Answer:** Keep the unread answer until a newer answer arrives or the user
reads it in the chat. Existing dismissal and pending-input precedence remain.

### Q2. A dismissed approval when a new approval arrives

Scenario: the user dismisses a notification for unresolved approval A, then
approval B arrives in that chat.

Recommendation: show the notification again because there is a genuinely new
request, with accurate current-request content and pending count. Dismissal
suppresses the previously seen state, not future requests in that chat.

**Answer:** Yes; a new approval restores the dismissed notification.

### Q3. Repeated interruptions from the same approval queue

Scenario: an approval notification is already visible; further approvals arrive,
or the user answers one and the queue advances.

Recommendation: the first pending request alerts, further requests silently
update its count, and advancing after a decision is also silent. A newly pending
request after the queue has emptied starts a new alert; normal result alerts
continue to obey their channel and preferences. The interruption behavior after
dismissal will be decided after Q2; this question concerns a still-visible alert.

**Answer:** Rejected the silent-update recommendation: “every notification
triggers sound.” Clarify routine rendering updates and monitoring separately;
do not silently keep the rejected queue-sound policy.

### Q4. What counts as reading a result?

The current app marks a chat read after opening/loading it; it does not verify
that the relevant answer was on screen. This question concerns clearing an
existing result notification, not reopening agreed foreground alert suppression.

Recommendation: clear when the user reaches the relevant result/latest reply in
the chat, not merely when opening the chat while viewing older messages. Do not
attempt to infer comprehension or require scrolling through every line.

**Answer:** Prefer reaching the particular notified latest answer. Full scrolling
is unnecessary. Reaching the bottom is acceptable if it is a sound simpler
approximation; investigate actual layout before selecting that mechanism.

**Fact finding:** `ProfileTranscript` already measures durable transcript section
bounds against its viewport for reader anchors. The bottom also contains live
work and request/task cards, so reaching it does not imply seeing the saved
answer. Honor the user's preferred exact-answer visibility rule; implement the
result identity/visibility callback without changing scrolling behavior. Side
result cards need their own visibility identity rather than a single tail key.

### Q5. Which pending input gets the single notification slot?

The current app has an approval queue, a separate clarification request, and a
separate secure-input request; no cross-type ordering is defined.

Recommendation: show the oldest unresolved input known to Wing, keep it stable
until resolved, and indicate the other pending inputs in a compact count. New
arrivals do not move the action target under the user's finger. Exact stable
ordering across reconnect remains subject to available stock request identity/data.

**Answer:** FIFO accepted across pending input types.

### Q6. Approval controls with message previews disabled

The agreed privacy preference hides the command/context, but the design has not
specified whether scope buttons should still execute without that context.

Recommendation: show a Review action that opens the chat; offer scope decisions
after the command can be reviewed there. Keep all supported direct scope buttons
in the normal preview-enabled notification.

**Answer:** Review opens the corresponding Wing chat.

### Q7. Approval controls while the phone is locked

Android's native action authentication flag does not directly apply to custom
RemoteViews click targets. Private content visibility alone is not an execution
gate, so locked-device behavior needs an explicit client design.

Recommendation: require device unlock before any approval/denial is submitted.
With previews enabled, continue the originally selected action after unlocking
and checking it is still current; Always still opens its agreed confirmation.

**Answer:** Device unlock is required.

### Q8. Offline or uncertain approval submission

Scenario: the user taps Once while unlocked, but Hermes is unreachable, or the
connection drops before Wing can confirm the response.

Recommendation: never queue a permission grant to send automatically later.
Retain the request with truthful failure/unconfirmed feedback, reconcile actual
state, and let the user explicitly retry if it is still pending. Do not claim
that an unconfirmed response failed: the server may already have applied it.
This is action submission behavior, separate from the agreed decision not to
add notification-posting retries.

**Answer:** User asks whether Android allows keeping the notification until
the button action succeeds. This is a feasibility question, not acceptance of
a deferred-send or retry policy. Official platform and stock response semantics
are being checked.

## Round 2 — answers recorded

### Q9. Boundary of “every notification sounds”

Recommendation: request sound for every new chat alert, newly arriving queued
request, and transition to the next pending request. Keep monitoring refreshes,
identical-state reconciliation, and transient submission-status redraws quiet.
Do not add app-level muting of meaningful queue changes. Android channel/DND
settings still govern actual sound.

**Answer:** Accepted; keep this simple and adapt later if it proves too noisy.

### Q10. Keep approval pending until confirmed

Android permits explicit notification update/cancellation after a custom button
tap. Recommendation: retain it while submitting; after confirmed resolution,
show the next request or clear/show the latest unread result as appropriate.
On failure or uncertainty, retain truthful feedback and reconcile; allow an
explicit retry if still pending, never queue an automatic permission grant for
later. External resolution/expiry still clears a stale request, and normal user
dismissal remains possible.

**Answer:** Accepted. Keep the pending notification on failed/unconfirmed
submission, reconcile, and offer an explicit retry; no deferred automatic grant.

### Q11. A command too long to inspect inside the notification

Android custom expanded content has finite height. Recommendation: retain the
supported choice controls, but when the command cannot be fully shown, have a
scope tap open the owning chat to review the full command and confirm that
choice before submitting. This changes the action's path, not the scopes offered.
The ordinary short-command direct path remains agreed.

**Answer:** Accepted. Additionally, notification-body taps must navigate to the
corresponding chat answer/request for review, not merely enter the chat.

### Q12. Explicit Mark read / Mark unread

Recommendation: Mark read in Wing explicitly clears that chat's result alert;
Mark unread does not recreate an old OS notification. Neither operation resolves
pending input. This recommendation was rejected below.

**Answer:** Rejected: “no mark read / unread, i never asked for that.” No manual
read/unread workflow is part of the revamp. Do not treat this as authorization
to remove unrelated existing chat-list features; the proposal concerns notification
behavior and should not grow a new manual clearing action.

### Q13. Counting mixed pending inputs

Scenario: two approvals plus one request containing three questions.
Recommendation: count remaining user decisions and label their kinds:
“2 approvals · 3 questions”, not “3 requests”. The same oldest input remains
displayed while its current question is answered.

**Answer:** Accepted as proposed: count remaining decisions and label the kinds.

### Q14. Reading on desktop

Current stock read state is chat-wide and desktop clears it on open, not when
the specific answer becomes visible. Recommendation: clear for actual answer
visibility in Wing (or explicit Mark read if Q12 accepted), not merely a remote
chat-read flag. Remote approval decisions still update/clear pending input as
already agreed.

**Answer:** Accept Wing-only read detection for simplicity. User wants completion
on desktop to clear Wing notifications and asks how the backend would notify
Wing. Verify actual cross-client resolution propagation and distinguish it from
merely opening/reading the chat; document connection/lifecycle limits.

## Fact-finding evidence from round 2

Latest upstream inspected: `ee17fff1936ddd73a7e90e5c37043b14d3a27163`.

- [Stock read watermark](https://github.com/NousResearch/hermes-agent/blob/ee17fff1936ddd73a7e90e5c37043b14d3a27163/hermes_state_sessions.py#L939)
  and [read mutation](https://github.com/NousResearch/hermes-agent/blob/ee17fff1936ddd73a7e90e5c37043b14d3a27163/hermes_cli/web_routers/sessions.py#L675):
  mark-read uses server time across the chat lineage, not a particular result ID.
  An untracked/null read watermark also yields unread=false, so that flag alone
  cannot prove reading the notified answer.
- [Desktop read behavior](https://github.com/NousResearch/hermes-agent/blob/ee17fff1936ddd73a7e90e5c37043b14d3a27163/apps/desktop/src/store/session-unread-remote.ts#L66)
  clears a loaded unread chat on opening.
- [Stock approval response methods](https://github.com/NousResearch/hermes-agent/blob/ee17fff1936ddd73a7e90e5c37043b14d3a27163/tui_gateway/methods_prompt.py#L1158):
  request.answer distinguishes ok/expired; approval.respond returns a resolved
  count. A successful transport response alone is not proof that approval was
  accepted. Missing responses over a failed connection are ambiguous.
- [Custom notification bounds](https://developer.android.com/develop/ui/views/notifications/custom-notification):
  expanded content can have as little as 252dp, so arbitrary commands cannot
  always be reviewed in full inside the notification.
- Android 16 [custom click dispatch](https://github.com/aosp-mirror/platform_frameworks_base/blob/android-16.0.0_r1/packages/SystemUI/src/com/android/systemui/statusbar/phone/StatusBarRemoteInputCallback.java#L327)
  sends the button intent without ordinary body-tap auto-cancellation. Wing can
  retain the notification, disable duplicate submissions, then explicitly
  update/cancel. Closing the notification shade is not removing the alert.
  The existing blanket autoCancel behavior must also change so a body tap does
  not clear input or an unread result before its actual resolution/read condition.
- [Android update/alert control](https://developer.android.com/develop/ui/compose/notifications/create-notification#update-notification):
  reusing a notification ID does not force silent updates; only-alert-once is
  an explicit control. Sound remains subject to the user's channel settings,
  system policy, and Android rate limits.
- A successful approval response means the decision was accepted (or accepted
  for compute-host relay), not that the command subsequently executed
  successfully. An expired/zero-resolution response requires reconciliation;
  it must not be described as a successful grant. If a request is later absent,
  that proves it is no longer pending, not who resolved it or which choice won.

## Round 3 — desktop completion and monitoring lifetime

Latest upstream inspected: `efa09f49c12fd05a991ffa972a6b0419ea104988`.
Successful desktop answers need not emit `request.cancel`. Stock request/approval
snapshots permit reconciliation; cancellation signals and database invalidations
can trigger checks but are not a complete success broadcast. See the
[updated requirements](2026-09-20-notification-improvements.md#follow-up-desktop-completion-and-synchronization)
for primary sources and the exact distinction from remote reading.

### Q15. Keep monitoring while input is pending?

The current foreground service can stop when no chats are doing active work,
even if input remains unanswered. Once the runtime/connection stops, Wing cannot
observe desktop decisions until reconnecting.

Recommendation: keep monitoring active while unresolved input exists, periodically
reconcile only the relevant pending requests, and return to normal idle shutdown
when there is neither active work nor pending input. This makes desktop completion
cleanup work while Wing is backgrounded and connected, at the cost of keeping
the service alive longer and doing additional network checks. It is not a push
guarantee after force-stop/process death or while offline.

Alternative: preserve the current service lifetime; synchronize desktop decisions
while Wing happens to be connected and otherwise clean up on reopening/reconnect.

Await the user's decision; do not silently extend service lifetime.

**Answer:** Rejected lifetime extension. Periodic reconciliation runs only while
the existing monitoring watcher is already on, to avoid additional phone resource
use. Pending notifications must not start or sustain monitoring by themselves.
Use bounded, shared checks for relevant chats, stopping with the watcher.

**Read-semantics clarification:** The user's follow-up labeled “q12” concerns
desktop read signals, not a request to add manual read/unread controls. The user
would accept polling a desktop read marker to clear an answer notification
**only if** that marker means the last chat message was read. This condition is
being checked against current stock desktop/backend source. The manual-controls
proposal remains rejected.

**Verified result:** At stock `b7d7d2929a10e0658a98a7a03f4531093e1480ed`, desktop
marks a chat read on selection, with no latest-message visibility condition.
The backend records server time when it processes the mutation, so messages
arriving between desktop selection and that mutation can be marked read without
being seen. Even watermark >= notified-message timestamp is insufficient.
The user's condition fails: do not use desktop read markers to clear Wing result
alerts. Request resolution/cancellation/expiry remains eligible for watcher-only
reconciliation. See the linked requirements for pinned primary sources.

No further behavioral question arises from this finding: the user already made
remote read clearing conditional on a semantic guarantee stock does not provide.
The user subsequently confirmed the design and authorized implementation.

## Records

- [Glossary](../../CONTEXT.md) contains settled terminology only.
- [State-based notification ADR](../adr/0001-chat-notifications-represent-relevant-state.md)
  records the already accepted architectural trade-off.
- [Watcher-lifetime ADR](../adr/0002-notification-reconciliation-shares-monitoring-lifetime.md)
  records the resource limit and accepted delay in background cleanup.
- Code/platform fact finding is delegated; findings will constrain later questions
  rather than asking the user to discover technical capabilities.

## Final answer-target decision

The user selected **option 2** for main completion events without a stable message
ID: open the latest available reply in the owning chat. Do not duplicate the answer
in the transcript or infer identity by matching prose. Exact request/task IDs
remain authoritative where available.
