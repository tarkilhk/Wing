# Network continuity

Owner-approved behavior, implemented 16 September 2026. This extends the Studio
conversation-preservation contract. Existing request timeouts are not increased.

## Two entry journeys

A notification opens its exact saved connection, profile and conversation before
network work. The destination remains visible through failure and retry. Verified
local reading history and the separately stored draft appear immediately when
available; otherwise a calm opening state explains automatic recovery. A timeout
or DNS error never means a conversation was deleted. A confirmed missing-session
response can explain that the conversation is no longer available. Newer taps
supersede older ones; repeated taps reuse the route.

Inside a conversation, retain its transcript, scroll, draft and partial response.
Reconcile the existing server session and refresh history after reconnection;
never replay a prompt with an uncertain submission outcome. Partial response text
stays visible until server history is available. New sends and message-edit actions are
unavailable during recovery; typing remains available. This introduces no offline
message queue and preserves the existing deliberate Queue workflow.

## Shared server identity

One observable state belongs to each exact saved connection identity, including
its credentials. Show an 8 dp LED to the left of the server name, separated by
4 dp, using Studio semantic colors rather than the selected accent:

- Green, steady: server access and observed live channels are available.
- Amber, softly pulsing over two seconds: recovery is underway.
- Amber, steady: server access and live chat differ in availability. Explain the
  affected capability, such as “Live updates interrupted”.
- Red, steady: unavailable, with recovery stopped because user action is needed
  or a bounded initial-opening/notification recovery cycle has finished.
- Neutral: an inactive saved connection has not been checked.

Reduced motion disables the pulse. Status details expose text for Server access
and Live chat and offer Retry after recovery stops. Status is shared across Chats,
conversation headers, Activity, administration and its drill-downs, drawers and
connection selection. Status targets are at least 48 dp. On connection-selection
rows, the LED opens details while the row/name retains its navigation action.
Conversation title/project navigation and server status have separate targets.

Short drops use the LED. After two seconds, a reserved metadata line can explain
recovery without moving the transcript. Reserve this space only in conversations;
Chats and other screens collapse the line when there is no recovery hint.
An empty notification destination uses
its central explanation rather than repeating the same cue above it. Technical
exceptions, DNS hostnames and timeout details do not appear as routine recovery
messages.

## Recovery and local reading

Live-channel recovery retries after 1, 2, 4, 8 and 16 seconds, then continues
once every 30 seconds while the connection controller is alive. The delay is
bounded; a temporary outage does not permanently stop observation. Sign-in, TLS
and other non-transient failures stop automatic retries and require user action.
Initial workspace opening and notification-target recovery retain their separate
bounded cycles. An Android network-return event, foreground entry or explicit
Retry attempts live recovery immediately. Android network availability only triggers verification;
it does not itself make the server green. A changed network route invalidates a
stale socket before reconnection. REST and live WebSocket observations remain
independent; administration success cannot clear a live-chat interruption.

Reading snapshots use the verified credential identity and never restore live
runtime state, approvals, credentials or pending writes. Limits are 12 profiles,
200 session rows and 100 projects per profile, 10 conversations per profile and
60 recent message rows per conversation. Oversized message rows are omitted;
older reading content is pruned to keep each connection snapshot under 2 MiB.
This is a recent reading cache, not a complete offline archive. Live status is
never restored from disk. Composer drafts retain their existing dedicated store.

## Verification

Regression coverage includes notification routing through failure and competing
taps, bounded retry delays, uncertain submissions, retained drafts and partial answers,
cold reading snapshots, credential isolation, independent REST/live states, and
narrow light/dark status layouts at 200% text size with reduced motion.

Actual Flutter recovery renders are generated under `build/network-review/` for
both journeys and themes. The Android debug build checks the native connectivity
callback; a physical-device 5G handover remains a separate device validation.

Validation record: full Flutter suite passed (1,812 tests, 10 skipped); final
transport, controller and navigation follow-up passed (87 tests). Static analysis
is clean and the Android debug APK builds successfully.
