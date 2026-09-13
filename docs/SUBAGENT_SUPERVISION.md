# Subagent supervision

D23 adds a per-chat subagent roster and live detail sheet. Open a chat's three-dot menu and choose **Subagents** to refresh its active children. Received subagent events also show a compact expandable roster in the transcript. Chats without known subagents gain no extra transcript row.

The detail sheet displays the child goal, status and available activity information, plus selectable live output. It refreshes the tail every two seconds while open and the app is active. After three consecutive failures, automatic refresh stops and Retry remains available. Closing the sheet stops its timer. Roster refresh is manual after the initial read; live events update known progress.

Steer appears when the backend says the child accepts guidance. Accepted steering is queued; the backend can still report missed delivery if the child finishes first. Rejected or failed steering retains the typed text. Interrupt reports an acknowledged request and waits for the backend to publish terminal state.

Every read and control uses the originating profile gateway, parent runtime and exact child ID. A later profile selection cannot redirect it. List replies cannot overwrite newer events or revive terminal rows, and controls require matching acknowledgement IDs. Replaced runtimes invalidate pending results.

## Server limits

The installed backend lists active children only and exposes up to the final 16 KiB of live output. Finished children disappear from that list and their tails may be unavailable. Completion events received by the open client retain a summary in that chat for the current runtime. There is no local subagent history, new execution engine or cross-session agent tree.

The view uses the backend's existing `subagent.list`, `subagent.tail`, `subagent.steer` and `subagent.interrupt` methods. See [source contract evidence](research/MOBILE_DELIVERY_CONTRACTS_2026-09-11.md). Live-server control and phone UI verification remain separate from fixture checks.

## Verification

The 2.7.0 source snapshot passed 1,029 tests with four opt-in skips and a clean analyzer. Controller checks cover sparse events, terminal status, stale snapshots, bounded tails, ownership and exact acknowledgements, including completion before an interrupt reply. UI checks cover the actual chat-menu entry, rejected draft retention, polling failure/retry, and a 320-pixel layout at 1.8x text with a 260-pixel keyboard inset. The signed Personal APK passed package/certificate checks and was installed in place and launched on the owner's phone as 2.7.0 / 21562. No live subagent has been interrupted or steered during these checks; live-server behavior QA remains.

## Refresh and unavailable output

A roster response can omit children that live events previously reported.
Refresh now retains those entries with an unconfirmed status and their last
known activity. It does not treat absence as completion. A subsequent event or
snapshot for the same child confirms its state again. Controls are disabled
while its status is unconfirmed. Runtime replacement clears that uncertainty
with the old roster.

The detail sheet keeps the latest received transcript when a subsequent read
fails or returns unavailable. It also displays up to 40 recent tool/progress
entries, including tool previews and event output tails, following Desktop's
activity stream. Snapshot refreshes do not overwrite that event trail with a
single tool name. Repeated adjacent entries are collapsed.

When Hermes returns no live transcript, Android says so and shows the received
activity instead. This does not create transcript content that the server has
not exposed. Terminal summaries and known children remain bound to the original
chat and profile.
