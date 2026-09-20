# Command approvals

The user needs to review a command, choose its approval scope or deny it, and
continue through every pending command without losing requests.

## Stock contract inspected

Verified upstream main on 20 September 2026 at
`e787529064152e690b5d5678bd2efe761dda6213`:

- [Gateway server](https://github.com/NousResearch/hermes-agent/blob/e787529064152e690b5d5678bd2efe761dda6213/tui_gateway/server.py): live `approval` server requests have a server-owned envelope ID and a separate `params.request_id` identifying the queue entry. Resume includes `pending_approval` and `open_requests`.
- [Prompt methods](https://github.com/NousResearch/hermes-agent/blob/e787529064152e690b5d5678bd2efe761dda6213/tui_gateway/methods_prompt.py): `approval.pending` returns the queue; `approval.received` acknowledges delivery; `request.answer` answers a live server request; `approval.respond` answers a queue entry restored from the pending list. Both response paths are current stock operations.
- [Desktop approval component](https://github.com/NousResearch/hermes-agent/blob/e787529064152e690b5d5678bd2efe761dda6213/apps/desktop/src/components/assistant-ui/tool/approval.tsx): commands use a bounded, scrollable monospace area; actions sit outside it; queue position advances independently of the remaining count.
- [Desktop prompt store](https://github.com/NousResearch/hermes-agent/blob/e787529064152e690b5d5678bd2efe761dda6213/apps/desktop/src/store/prompts.ts): requests deduplicate by queue ID and preserve live server-request metadata during pending-list replay.

Changes are entirely client-side. No backend modifications or deployment are
needed. The obsolete `approval.request` wire event is replaced by the current
`approval` server-request contract.

## Layout decision

Two arrangements were considered:

1. Inline: approval heading and queue position → bounded command → scope buttons.
2. Summary row: command summary → tap to open a sheet with command and buttons.

The inline arrangement keeps the primary action in the conversation without an
extra tap or an additional navigation state. It uses the existing Studio card,
spacing, surfaces, monospace typography and buttons. The command area is at most
160 dp tall and becomes shorter with enlarged text to make room for the controls.
The full command remains selectable and scrollable; it is not truncated.

## Behavior and regression coverage

- Attention alerts are delivered even while the chat is visible. Android uses a
  dedicated high-importance attention channel. App notification preferences and
  platform permission still govern delivery; completion suppression is unchanged.
- Requests queue by their backend IDs. Duplicate delivery updates metadata without
  another alert. A response removes only its own request; later requests remain
  actionable with progress such as 1/2 → 2/2.
- Live delivery, resume and response settlement reconcile against `approval.pending`.
  Runtime, revision and read-generation checks prevent a stale read from erasing
  newer requests or restoring answered ones. Pending-list requests are acknowledged.
- Cancellation matches the server-request ID. A stale UI action cannot approve a
  different queue entry. Failed submissions retain the queue for retry.
- Controller, real-loopback WebSocket and Android plugin-seam tests exercise
  delivery, exact IDs, notifications, queue recovery, cancellation and response races.
- The actual chat screen is rendered at 390 × 844 in both themes at 100% and 200%
  text size. Widget checks exercise independent scrolling, full-button reachability
  and disabled actions. Review images are generated under `build/approval-review/`
  with `CAPTURE_APPROVALS=true` and `CAPTURE_FONT_DIR` pointing to the test fonts.

The reproductions identified three causes: visible-chat notification suppression,
an unbounded command widget, and single-request state coupled to an obsolete wire
event. Testing multiple approvals through the real socket and pending-list replay
protects the full interaction rather than only the command model.

Validation on 20 September 2026:

- Focused controller, notification, transcript, recovery and transport run: 221
  tests passed. The two typed approval-RPC checks also passed. A subsequent real
  socket run passed all four cases, including two queued approvals with distinct
  response IDs; command-model checks passed after preserving exact whitespace.
- Repository-wide `flutter analyze --no-pub --fatal-infos`: no issues.
- Full suite: 2,603 passed, 12 skipped, one old resume fixture failed because it
  omitted the current required approval ID. That fixture was corrected and its
  reopen/reconciliation case passed in the focused rerun. The entire suite was
  not repeated after the fixture correction.
- Both themes and both text scales were rendered and inspected. The enlarged
  text review prompted a shorter command viewport to preserve button reachability.

## Live backend follow-up

Inspected stock upstream commit `59f9ff8dbc75b9c4f07ae10174df730f7882a505`.
The missing integration was the per-connection `client.capabilities` announcement:

- [Server request admission](https://github.com/NousResearch/hermes-agent/blob/59f9ff8dbc75b9c4f07ae10174df730f7882a505/tui_gateway/server_requests.py)
  withholds requests from transports that have not advertised `server_requests`.
- [Capability handler](https://github.com/NousResearch/hermes-agent/blob/59f9ff8dbc75b9c4f07ae10174df730f7882a505/tui_gateway/methods_voice.py)
  records that support on the calling transport, so reconnecting must advertise
  again. Stock dispatch accepts the announcement as a JSON-RPC notification.
- [Shared desktop channel](https://github.com/NousResearch/hermes-agent/blob/59f9ff8dbc75b9c4f07ae10174df730f7882a505/apps/shared/src/json-rpc-channel.ts)
  announces support and rejects unsupported server requests with `-32601`.

The live emulator reproduction used Luna and two print-only `execute_code` calls.
Before the fix, both tool results reported that approval was withdrawn because
the attached client could not answer requests; Wing received no approval frames.
The earlier mock servers always delivered requests and therefore missed this
admission rule. A real-loopback regression now reproduces withdrawal without the
announcement and checks both initial connection and reconnect, including an
observer that submits immediately when connected.

Wing sends the announcement before publishing the connected state. Socket
ordering places it before session operations. Unsupported server requests get
the standard terminal error instead of silently waiting for a timeout. No backend
changes or compatibility fallback are involved.

Live Android validation used the user's existing backend and session-specific
`gpt-5.6-luna`, with low reasoning. With explicit permission, each scenario briefly
selected Manual approval mode and restored Smart afterward:

- Two sequential print-only code calls: both requests appeared, both Android
  **Allow once** actions succeeded, and the turn completed.
- Two parallel terminal calls removing distinct, nonexistent test-owned `/tmp`
  paths: both requests were pending together; the UI advanced from **1/2** to
  **2/2**, both Android actions succeeded, and the turn completed.
- Four actual emulator render captures cover the first and second request in
  each scenario. No desktop approval was needed.

The opt-in reproduction is `integration_test/approval_queue_live_test.dart`.
It reads an explicitly authorized connection from the emulator app's private
`files/approval-connection.json`; credentials must not be committed or passed as
build defines. Run with `RUN_LIVE_APPROVAL_QA=true`. The additional
`APPROVAL_QA_MANUAL=true` flag requires permission to temporarily change the shared
profile setting; the test restores the original mode on success and failure.

Validation after the follow-up: both live scenarios passed; 194 focused approval,
WebSocket, reconnect, browser and prompt checks passed after their fixture servers
were updated to consume connection-level negotiation; repository-wide static
analysis reported no issues. The restored Smart mode was independently read back
from the live API, and temporary connection copies were deleted from the host and
emulator.
