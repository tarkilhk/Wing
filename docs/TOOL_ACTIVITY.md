# Readable tool activity

Conversation compression uses stock `status.update` at inspected upstream main
`0e21933114c911075782d5744cee5403996d38ae` (8 October 2026).
`ChatRuntime` owns a per-session compression phase independent of turn execution
and slash-command lifetime. `compacting` and `compressing` activate it;
`compacted`, `ready`, resumed main output/tool events, turn completion/errors and
an explicit `running: false` snapshot retire it. A running heartbeat, usage count
or child activity cannot retire it. A same-runtime running resume preserves the
phase; replacing the runtime clears it. Compression events invalidate older
runtime reads. The controller publishes resumed output immediately so the label
does not remain behind the streaming throttle.

The existing Studio status row above the composer shows “Summarizing
conversation…” with an 18 dp compression glyph and the shared text shimmer.
It wraps at enlarged text and becomes static with reduced motion. Input requests
and recovery retain priority. No extra transcript card or reserved empty row is
introduced. The phase is a passive observation; existing turn and command owners
retain submission admission.

`test/profile_activity_status_test.dart` guards the actual controller-to-status
path, manual pending command lifetime, session isolation, resume read invalidation,
terminal/resumed-work ordering, input priority and rendered phone layouts in both
themes at ordinary and doubled text. These are behavioral guards: a static source
check cannot establish delivered event order or rendered wrapping. The original
automatic/manual regression was proven red before implementation. Run
`flutter test --no-pub test/profile_activity_status_test.dart`.

Open Activity in a conversation, then Tools. Every backend call has an individual
action row: a single-line action title, one single-line input detail and timing.
URLs omit the HTTP(S) prefix in the subtitle; complete inputs remain in details.
Warnings and failures replace the input subtitle with a one-line exception.
Missing backend timing is shown as a dash with an explanatory tooltip. Expand a
row to read its result. Vision calls show their exact
`image_url` input using the existing bounded image preview and full-screen viewer,
followed by the question and returned analysis. Raw details exposes selectable,
copyable tool identity, inputs and output without client payload truncation.
Normal completion, success and unchanged-skill status add no header notice.
Pending action titles and approximate live counters identify running work;
warnings and failures remain visible without adding a third header line.
Tool headers have exactly two single-line text rows, zero vertical padding and
no minimum row height or inter-row spacing. Both lines ellipsize at the available
width and grow with text scaling. Full titles and inputs are available expanded;
16 dp icons and
rotating arrows fit the compact text rows.
Tasks, Agents, Work and Thinking retain their selection;
approvals and questions remain outside tool disclosures.

## Stock backend contract

Inspected latest upstream Hermes main commit
[`53fefae5d74312a534063e1b1ef932c0cf98e1e9`](https://github.com/NousResearch/hermes-agent/commit/53fefae5d74312a534063e1b1ef932c0cf98e1e9)
on 7 October 2026. Wing requires no
backend patches, plugins or custom endpoints. Sources are upstream
`tui_gateway/contracts/events.py`, `tui_gateway/tool_progress.py`,
`tui_gateway/session_history.py`, `tui_gateway/server.py`, `tools/tool_labels.py`,
`tools/vision_tools.py`, `hermes_cli/web_routers/sessions.py` and
`apps/desktop/src/i18n/en.ts`.

- `tool.generating` announces preparation, not an executed call or start time.
- `tool.start` supplies `tool_id`, `name`, `context`, `args` and `labels`. It does
  not expose the backend's internal start timestamp. The runtime records the
  monotonic phone receipt time only for a live start with a backend ID. Displayed
  elapsed time is approximate and excludes time before delivery. It needs no
  clock synchronization. Replayed or missed starts cannot produce a timer.
- `tool.complete` supplies the same call identity, `duration_s`, delivered input,
  result and labels. Backend duration replaces the estimate; completion without
  a duration stops the estimate and leaves timing absent. Completion alone means
  completed, not succeeded. Explicit result success, errors, terminal exit codes,
  unchanged skill status and returned 404 pages determine readable outcomes.
- A saved tool row is joined to an assistant `tool_calls[].function` by exact
  `tool_call_id`, even when the assistant has no prose. Inputs outside the loaded
  history window stay unavailable; no adjacency/name guesses are made.
  Saved connector labels come from the REST assistant row's
  `tool_call_labels[tool_call_id]`, using the same exact identity join.
- Stock saved history does not normally persist tool durations. The reading owner
  retains up to 256 received call observations per chat and enriches matching
  actual saved rows with delivered inputs, labels and final durations. It never
  invents transcript rows. The existing bounded reading cache now retains tool
  identity, readable input metadata and received final durations. On restoring
  the cache, `TranscriptReading` retains measured durations across authoritative
  refresh only when both the durable row ID and tool call ID match. Fresh
  backend durations take precedence, including zero. Cached rows never start
  timers or regain execution authority. Cache limits still apply (60 recent
  rows per chat, ten recent chats per profile); timing never received or already
  pruned cannot be recovered from stock history alone. The independent timing
  index described below now preserves received saved-row measurements beyond
  those preview limits.

## Missed completion recovery, 8 October 2026

Verified latest unmodified Hermes main
[`ad12263a5ed43109d3942a8af04d4cef210fa6ae`](https://github.com/NousResearch/hermes-agent/commit/ad12263a5ed43109d3942a8af04d4cef210fa6ae).
Stock [`session.events.since`](https://github.com/NousResearch/hermes-agent/blob/ad12263a5ed43109d3942a8af04d4cef210fa6ae/tui_gateway/methods_session.py)
returns retained event objects with `type`, `session_id`, `payload` and `seq`.
The [`event ring`](https://github.com/NousResearch/hermes-agent/blob/ad12263a5ed43109d3942a8af04d4cef210fa6ae/tui_gateway/event_replay.py)
is bounded to 512 events and 4 MiB per session, with additional process limits.
The stock REST history still omits ordinary tool durations.

`ProfileGateway.completedToolActivities` reads the current runtime's retained
completions from `last_seen: 0`, selects exact matching runtime identities and
valid measured durations, and deduplicates in last-completion order.
`TranscriptReading.refresh` reads those receipts alongside the authoritative
saved page and enriches actual rows by exact tool-call ID. Live measured receipts
win over a delayed recovery response. The existing 256-receipt bound retains the
newest recovered completions. The controller rejects reads after runtime
replacement; the reading generation rejects superseded or retired reads.
Replayed starts, turn events and pending inputs never enter execution owners.
Partial replay can still supply a retained measurement for an exact call; it
cannot establish a complete turn. A failed timing read leaves saved messages
readable. Recovered durations enter the existing passive reading cache.

`TOOL_TIMING_RECOVERY` is guarded by
`test/profile_execution_activity_test.dart`: the actual controller/history path
first reproduced a retained 0.195-second completion becoming unknown, then
passed with recovery. Cases cover partial replay, wrong runtimes, absent rows,
invalid and zero timings, duplicate completions, full-ring retention, failed I/O,
live completion races and retired reads. Static analysis cannot establish which
events remain in the ring or their asynchronous ordering; these behavioral
checks own the invariant. Run
`flutter test --no-pub test/profile_execution_activity_test.dart`.

Timing is still unavailable when no measured completion remains in the server's
ring or Wing's bounded reading cache. A server restart clears the ring. This
client change does not infer execution duration from saved message timestamps.

## Recovery across runtime replacement, 8 October 2026

Verified current unmodified upstream main
[`3090ef7731177154ab74aacd80b2f0d7e803dd14`](https://github.com/NousResearch/hermes-agent/commit/3090ef7731177154ab74aacd80b2f0d7e803dd14).
A cold `session.resume` mints a fresh eight-character UI runtime ID. The saved
conversation ID and this runtime ID are different identities. Replay buffers
remain keyed by the original runtime after it is retired; querying only the new
runtime can return no completions even while older measurements are retained.

Stock `hermes_cli/web_routers/status.py` exposes filtered `GET /api/logs` reads.
`tui_gateway/prompt_turn.py` emits an explicit `tui prompt accepted` identity
record containing `ui_session`, `session_key` and `agent_session_id`, without
prompt content. `ProfileGateway` reads at most 500 matching process GUI log lines
and accepts only this record's exact saved-session identity. It queries up to 64
recent associated runtime rings, with at most four concurrent reads, and retains
the current runtime's completion measurements last. Each failed timing read is
independent; missing logs cannot discard a current runtime's measured receipts.

Only valid `tool.complete` receipts with the queried runtime's exact identity
enter `TranscriptReading`. The existing exact tool-call join enriches real saved
rows, live measured receipts remain authoritative, and generation checks still
reject superseded reads. Log text, replayed starts, turn state and pending inputs
are never persisted or adopted as execution authority. Received measurements
enter the existing independent timing index.

Recovery requires both a retained runtime association and a retained completion.
Rotated GUI logs, disabled identity logging, evicted rings and server restart can
make old measurements unavailable. This is bounded recovery through stock APIs,
not durable backend timing storage or a timestamp estimate. Inspect the actual
saved message and its measured completions across a cold reopen before claiming
historical timing recovery; a current-runtime-only replay is insufficient.

## Measured timing retention independent of previews, 8 October 2026

Verified current unmodified upstream main
[`daa9593a03adf0040f49444126b313fcf985c459`](https://github.com/NousResearch/hermes-agent/commit/daa9593a03adf0040f49444126b313fcf985c459).
`tool.complete` still supplies `duration_s`; ordinary saved history does not
persist it. Recovery from `session.events.since` is limited to the event ring.
An older completion evicted from that ring cannot be reconstructed as a measured
duration from saved message timestamps.

`TranscriptReading` retains every measured saved-row timing independently of
the 256 full receipt observations and the 60-row preview. Its timing revision
changes only when an actual measured row/call pair changes. A restored index
enriches saved rows only by that exact pair; a fresh backend duration, including
zero, replaces the retained measurement. Timings have no execution authority.

`WorkspaceSnapshotStore` persists these small indices separately for each
verified connection identity, profile and durable chat ID. The ordinary preview's
row, chat and byte limits do not prune them. Inputs and outputs remain in the
bounded preview; the index contains only saved-row identity, backend call ID and
measured seconds. Changed indices and previews share one ordered write queue;
larger indices encode off the UI isolate. The controller restores an index on
every chat admission and writes changed indices for loaded chats independently
of the ten-chat preview limit. Confirmed local chat-deletion cleanup removes the
corresponding index after earlier writes.

This retention change preserves available measurements. A measurement already
absent from both Wing and the server remains unavailable. No server patch,
profile-setting change, or timestamp-derived measurement is introduced.

## Timing retention and uniform tool headers, 8 October 2026

Verified current unmodified upstream main
[`7dab93b06e2bb3757dc18229169efcee1b5b47a3`](https://github.com/NousResearch/hermes-agent/commit/7dab93b06e2bb3757dc18229169efcee1b5b47a3):
`tui_gateway/tool_progress.py` still emits `duration_s` on completion and no
backend start timestamp; ordinary saved session rows still omit this timing.
The client regression reproduced a received 1.25-second duration becoming absent
at reading-cache encoding. The typed cache projection now preserves this passive
fact, and refresh retains it by exact durable-row/call identity. No timestamp
subtraction or locally invented completion time fills missing historical timing.

`ToolCallPresentation` owns the one-line input detail. Supplied label previews
win. Browser scripts use a literal input URL, leading step comment or code
preview; no script is evaluated and no URL is borrowed from another call.
File tools show paths, file searches show pattern and path, preview tools show
action and target, tool discovery shows requested names, and delegations show
task count and first goal. Other tools use their delivered query, command,
image, prompt, reference, selector or context. If none is supplied, the subtitle
says so. Stock schemas inspected include `tools/browser_use_cli.py`,
`tools/preview_tool.py`, `tools/drive_preview_tool.py`, `tools/tool_search.py`,
`tools/tool_labels.py` and `agent/display.py`. When input metadata is unavailable,
an explicitly delivered result URL/path or delegation goal supplies the detail.

Code calls include their delivered `code` input, and memory retention includes
its delivered `content` input. Both keep a visible second line even when input
metadata is missing. `test/profile_tool_call_test.dart` exercises those exact
calls as live receipts and saved rows at 360 dp, in both themes at ordinary and
doubled text, including missing inputs and equal collapsed heights.

Wing selects Material icons locally through `ProfileToolCall.iconFor`, using
the delivered tool name rather than the displayed caption. Its single constant
lookup maps commands to terminals, scripts to code brackets, file reads to
documents, edits to edit notes, patches to differences, file searches to a
document search, browsing to a globe, tasks to a checklist, scheduling to a
calendar and delegation to a branching tree. The `hindsight_` namespace and
`memory` use the outlined brain/head glyph. Unknown tools and connector bridges
use a neutral extension glyph. Adding a tool's icon means adding one lookup
entry; every live and saved tool row uses the same policy. Captions remain
separate: the checked-in English catalog comes from Hermes Desktop, and
connector labels can come from delivered events. Hermes supplies no icon ID.

The icon and subtitle changes use the existing stock `name`/`args` delivery,
verified at latest upstream main `2943ee6f19a2abd0cc93384db55643469e80dfcb` in
`tui_gateway/tool_progress.py` and `tools/code_execution_tool.py` on 8 October
2026. No backend changes are required. The widget regression also checks the
rendered icon for each activity family and proves that a connector caption does
not override its underlying tool identity. Static checks cannot establish the
meaningful subtitle produced from a delivered payload or the rendered glyph;
these behavioral checks guard those properties.

Behavioral guards cover the actual receipt → history → cache encode → restore →
refresh → timeline path in `test/profile_execution_activity_test.dart`, including
row/call mismatch rejection and fresh zero-duration precedence.
`test/reading_snapshot_message_test.dart` checks typed metadata and excludes
runtime fields and invalid timing. `test/profile_tool_call_test.dart` checks
explicit unknown timing without reading a clock. The presentation cases in
`test/tool_call_presentation_test.dart` and rendered tab cases in
`test/profile_activity_details_layout_test.dart` enforce meaningful second lines,
equal collapsed heights, one-line truncation and zero padding in both themes at
normal and doubled text. These are behavioral properties: static analysis cannot
establish which timing was delivered or the rendered height of actual text.

## Labels and ownership

Supplied connector/MCP `labels[].text` and `preview` take precedence. The desktop's
23 built-in English action titles are generated into
`lib/core/presentation/desktop_tool_labels.dart`; skill reading has a small
explicit title. Other current tool names are humanized. No model request, legacy
alias catalog or per-tool backend dependency is introduced. To update the desktop
catalog after inspecting a new upstream commit:

```sh
python3 tools/generate_tool_labels.py /path/to/apps/desktop/src/i18n/en.ts FULL_COMMIT
dart format lib/core/presentation/desktop_tool_labels.dart
```

`ChatRuntime` owns call identity, phase, receipt time and merging. A duplicate
start preserves its first receipt; a late start cannot reopen a completed call.
`TranscriptReading` owns receipt enrichment and immutable saved rows.
`TranscriptTimeline` owns the pure saved input join.
`ToolCallPresentation` interprets delivered data for readable display and keeps
the raw result intact, including the external-data wrapper. The shared
`ProfileToolCall` renders both live and saved facts. Ordinary disclosure state
follows the backend call ID across live-to-history
handoff, while explicit notification focus opens its target independently.
Only `ActivityTime` ticks; it cancels its timer on completion, hidden tabs,
app background and disposal.
Image I/O continues through the owning chat's existing attachment loader.

## Regression and visual verification

Structured `results` entries are not necessarily web sources. Skill-management
batches supply operation receipts containing `name`, `action`, `file_path` and
`success`, rather than a URL or snippet. Verified against latest stock upstream
main [`9241b0c60fd2efcc62b589ecae64d119d846c0dc`](https://github.com/NousResearch/hermes-agent/commit/9241b0c60fd2efcc62b589ecae64d119d846c0dc)
on 7 October 2026, in `tools/skill_manager_batch.py`,
`tools/skill_manager_tool.py` and `tui_gateway/tool_progress.py`.
`ToolCallPresentation` renders each receipt's delivered scalar facts, uses its
name as the heading and avoids repeating that name in its body. Existing web
links and excerpts retain their source presentation. Empty/whitespace-only
result bodies are omitted; nested fields and the exact original result remain
copyable under Raw details. The same projection serves live and saved calls.

`TOOL_RESULT_CONTENT` is guarded by the skill-batch and blank-result cases in
`test/tool_call_presentation_test.dart` and `test/profile_tool_call_test.dart`.
They reproduce the former empty Result headings with the current stock batch
shape and verify all four receipts, live/saved parity, web content, raw-copy
fidelity and readable phone layouts in both themes at normal and doubled text.
This requires behavioral checks: a static source pattern cannot establish which
fields an actual delivered result contains or whether its rendered body is empty.
Run `flutter test --no-pub test/tool_call_presentation_test.dart test/profile_tool_call_test.dart`.
For production-widget captures, add `--dart-define=CAPTURE_TOOL_RESULTS=true`
and `--dart-define=CAPTURE_FONT_DIR=<Flutter SDK>/bin/cache/artifacts/material_fonts`;
images are written to ignored `build/tool-results/`.

`test/tool_call_presentation_test.dart` guards completed versus success semantics,
desktop/connector/unknown titles, raw wrapper preservation, exact saved call
correlation, no timers for preparation/replay/missed starts, independent parallel
calls and terminal event ordering. `test/profile_tool_call_test.dart` guards
counter ticking/visibility/background/final duration, original vision input,
copy fidelity and light/dark enlarged-text rendering. These are behavioral
guards because source pattern checks cannot prove asynchronous ordering or timer
lifetime. `test/profile_execution_activity_test.dart` guards receipt enrichment
across authoritative history refresh and rejects enrichment of unrelated IDs.
Existing tab, disclosure and transcript tests cover retained selection, focus,
scroll anchoring, expansion across added rows and separation from answers.
`CompactActivityRow` owns the header geometry for tools and saved agents. Its
interface accepts text lines, timing and optional details, with no padding or
minimum-height overrides. `ARCH_ACTIVITY_DENSITY` requires the two header
builders to construct that canonical row directly; [the rule contract](../tools/architecture/rules/activity_density.md)
defines its finite scope and legitimate detail spacing.
`test/profile_activity_details_layout_test.dart` measures zero vertical header
padding and inter-row gaps through the real saved-history section and tool
group wrappers, including automatically discovered activity tabs, in both themes at
normal and enlarged text, including long ellipsized tool labels, exception subtitles, targets
and delivered durations. Saved-agent goals continue to wrap. The height budget uses the tallest parallel content
column, so a timing label cannot hide added padding. The timer itself must fit
its text without vertical padding and align with the top of the row. It also rejects empty
saved-agent disclosures, including whitespace-only output, while requiring real
saved output to remain expandable. These are behavioral guards because static
checks cannot establish actual rendered height or the available payload at
runtime. The same cases run on Android through
`integration_test/profile_expansion_scroll_test.dart`.
The transcript scroll controller retains both ends of the corrected scroll range
across lazy-list layout estimates. Switching a long Tools section to a short
Agents section holds the tapped tab and its content in view, including when the
new height would otherwise cross the natural bottom boundary. Collapsing a
disclosure instead clamps its corrected position to the natural bottom boundary
and clears any reserved space below the content, during layout before painting.
Expansion and tab selection explicitly allow that temporary space; collapse does
not. Explicit navigation to Latest also clears the temporary range.
`test/profile_transcript_test.dart` checks repeated expand/read/collapse cycles
for saved and live tool activity without tapping Latest, every collapse animation
frame, retained parent rebuilds, both themes and enlarged text. This is a
behavioral guard because static analysis cannot establish the viewport's actual
content extent or the empty space left after animated height corrections.
The same test file also checks every tab transition frame, repeated switches,
long following content, both themes
and enlarged text. Its answers use the production asynchronous Markdown renderer
and the test waits for reparsing after each switch. Fixed-height answer stubs
cannot detect lazy Markdown rows collapsing when they are recreated.
The transcript retains measured row heights only for its current stable row keys.
A recreated row keeps its measured height while Markdown is preparing, then uses
its real content height. The scroll controller also includes measured changes in
newer rows while a disclosure is anchored, including first-time Markdown growth.
Sliver-applied corrections are accounted for once. Loading registrations end on
completion, failure, reparenting or disposal; no rendered content is retained
outside its normal widget lifetime. This is a behavioral guard: static analysis cannot establish
sliver height estimates or painted tab position.

Inspect production widgets at 360 dp with ordinary and enlarged text in both
themes, including expanded vision and raw details. Store captures under ignored
`build/` or outside the repository, as required by `docs/PERFORMANCE.md`.

## Tasks and Agents

The Tasks tab retains backend order and parent indentation. Each status icon owns a separate semantics container so its completed, active, pending or cancelled label remains independently discoverable beside the task text. `test/profile_todo_icons_test.dart` checks these labels and layout in both themes at normal and enlarged text; static checks cannot establish the rendered semantics tree. Full task text stays
selectable, with a separate Pending, In progress, Completed or Cancelled line.
Its summary counts each backend state; cancelled tasks are not counted as
completed. These are passive observations, not editable checkboxes. Stock todos
have no start or duration field, so no task timer or estimated progress is shown.

The Agents tab uses individual task rows with status and time on their own line,
readable current tool/activity below, and subordinate model/tool-count metadata.
Tap a row for the existing output, steering and interrupt sheet. Details exposes
copyable backend identity, model, tool count, start and final duration when present.
Refresh, loading, retry and last-seen uncertainty remain owned by the existing
supervision session. An unconfirmed running row has no advancing counter and
cannot be controlled from the sheet.

Inspected latest stock upstream main
[`13dc3a73895aff1f823c1566bc1dd9b52fe35b65`](https://github.com/NousResearch/hermes-agent/commit/13dc3a73895aff1f823c1566bc1dd9b52fe35b65)
on 7 October 2026, specifically `tui_gateway/contracts/events.py`,
`tui_gateway/methods_subagents.py`, `tools/delegate_tool_registry.py` and
`tools/todo_tool.py`. `subagent.list` supplies `started_at` as Unix seconds;
`subagent.complete` supplies `duration_seconds`. The live label subtracts the
backend start from phone time, clamps negative clock skew to zero and marks the
result approximate. No start is inferred from opening a tab or receiving an event
without a timestamp. Queued, unconfirmed and terminal observations never tick.
A delivered completion duration replaces elapsed time; a completion without it
leaves timing absent. Duration is retained across canonical event merging.

`ActivityTime` is the shared display-only ticker for tools and agents; only its
label rebuilds once per second. Its two clock sources remain explicit: monotonic
receipt time for tool starts, backend Unix time for agent roster starts. Hidden
tabs, app background and disposal cancel ticking. No new backend operations or
history migration are introduced.

`test/gateway_insight_test.dart` guards terminal duration merging and invalid
numbers. `test/profile_tool_call_test.dart` covers backend epoch calculation,
clock skew, hidden labels and final duration. `test/profile_execution_activity_test.dart`
covers all four task states, backend order and parent indentation at both text
sizes and themes. `test/profile_subagent_panel_test.dart` covers agent states,
missing/queued/unconfirmed timing, metadata copying and retained controls/output.
These are behavioral checks: static source rules cannot establish rendered
reachability, timer lifetime or asynchronous terminal ordering. Inspect both
production tabs and the detail sheet at 360 dp and 200% text in both themes;
private capture artifacts remain under ignored `build/` or outside the repository.

## Restoring Activity from saved chats

Saved agents expand only when a nonblank summary or error was delivered.
Recorded background dispatches without output show the full goal and dispatch
notice as passive text, without a chevron or expansion action. Saved-agent rows
share the zero-vertical-padding density of tool headers.

Opening a chat reads its active `subagent.list` roster without requiring the
Agents tab to be visible first. Its existing scoped read admission prevents
late results from adopting agents into another runtime.

Every saved Activity section now projects its own full todo snapshot and
`delegate_task` results. The last delivered `{revision, todos}` snapshot in
that section wins, including an empty list. Task order, parent links and states
come from that payload, never from the present-day chat's task list.
Synchronous child results join their `task_index` to the exact parent call's
input task. Saved goals, model calls, summaries, errors and nonnegative
`duration_seconds` are inspectable. Background dispatch results expose the
reported goals and inline results; a historical dispatch is labelled as a past
dispatch, never as presently running. No timer starts on history restore.
Existing current-runtime tabs take precedence when sharing the latest section.

Saved child results are passive values with no invented subagent ID or control
capability. Expand a saved row to inspect output; steering and interruption
remain exclusive to verified current-runtime agents. The original tool result
remains available under Tools, including any fields not summarized in Agents.
Async completion notices retain their existing expandable result display;
stock notice metadata does not supply a structured per-child roster.

Verified latest unmodified upstream main
[`503a6b60e5357228d26196e606099e0ac79b7fdf`](https://github.com/NousResearch/hermes-agent/commit/503a6b60e5357228d26196e606099e0ac79b7fdf)
on 7 October 2026: `tools/todo_tool.py`, `tools/delegate_tool_dispatch.py`,
`tools/delegate_tool_child_run.py`, `tui_gateway/methods_subagents.py`,
`tui_gateway/tool_progress.py` and the saved session APIs. Ordinary saved tool
rows still do not contain duration. Received durations survive within the client
reading-cache bounds described above; other missing times remain a backend
history limitation and are never reconstructed from message timestamps.

`test/profile_combined_activity_test.dart` reproduces/restores both historical
tabs through the real timeline and widget path. `test/saved_activity_test.dart`
guards snapshot clearing, exact child-index joins, background dispatch and
malformed/unrelated payloads. `test/profile_subagents_test.dart` verifies roster
discovery on opening a saved chat. Exception-only tool headers retain delivered
timing in `test/profile_tool_call_test.dart`.


## Inline requests and receipts

Expanded Tools use a single detail card aligned with the leading activity icon.
Code and command requests are paired with literal output; read-file requests
show the exact path/range, supplied numbered content and reported file limits.
Writes expose requested content and server verification when supplied. Patch
requests expose Find/Replace or the requested patch separately from the returned
unified diff; the client never synthesizes an applied diff from intent. Vision
shows the exact requested image/question and backend analysis or native image
receipt. Search matches and other structured tool records use readable fields.
Both live and saved calls use the same pure `ToolActivityDetails` projection.

Every activity text body uses the same vertically scrollable inline viewport
of up to 160 dp, retaining all received text. There is no 12-line/character
preview truncation, Preview row, Full text row or content-expansion control.
Copy and the existing full-view icon remain in the section header. The full view
shows the same received content in a page scroll; it never reruns the activity.
Markdown is used for explanatory prose and Markdown file receipts; code files,
logs and diffs remain literal. Wrapping and horizontal source/table scrolling
stay within their own region. Server truncation and partial-file observations
remain distinct from local scrolling. Raw details retain exact input/output
values and use the same scrolling component, as do additional backend labels.
The existing profile-scoped image loader owns image access and original viewing.

Read-file receipts have one compact path/range header with eye, copy and share
icons. Markdown receipts render inline in the shared 160 dp viewport, removing
only the stock numbered-line prefixes for display; copy retains the original
receipt. Other files use the literal viewport. There is no separate Read options
or content toolbar. Raw/formatted switching lives only in the full Markdown
file viewer, with icon-only copy/share. That viewer retains its own backend
file read, truncation disclosure, relative links, download and delivery owner.

Latest unmodified upstream main inspected on 8 October 2026:
[`dde8800ed91c6e128064a17d5db914d74622594b`](https://github.com/NousResearch/hermes-agent/commit/dde8800ed91c6e128064a17d5db914d74622594b).
`tools/file_tools.py`, `tools/file_operations.py`, `tools/file_operations_common.py`,
`tools/vision_tools.py`, `tools/image_generation_tool.py` and
`tui_gateway/tool_progress.py` establish these request/receipt fields. The stock
file editor is `patch`; no new legacy tool alias is introduced. Native vision's
`_multimodal` receipt confirms pixels supplied to the agent, not a returned
analysis. Exit codes and server verification are shown only when supplied.

Behavioral guards in `test/tool_call_presentation_test.dart` protect request/result
fidelity, empty replacements/files, failed patches, reported limits, structured
matches, native vision and absent exit codes. `test/profile_tool_call_test.dart`
protects icon-only exact copy, leading-icon alignment, Markdown scrolling/full
view and rendered 390 dp/320 dp doubled-text cards in both themes. Runtime payload
semantics, clipboard values and rendered reachability cannot be established by
source linting alone. Existing compact-header, disclosure and live/history tests
remain applicable. Capture with `CAPTURE_TOOL_RESULTS=true` and
`CAPTURE_FONT_DIR` containing Roboto, MaterialIcons and DejaVuSansMono font files.


### Resource action refinement

File/image headers retain Preview (eye), Share and Copy icons. Generated images
receive the same actions on their returned target. Preview opens the existing
scoped output viewer; Share downloads original bytes and opens the platform
share sheet. The actions use exact supplied resource targets and never rerun the
tool or replace the stored receipt with current file contents. The workspace
captures the original chat/profile file owner and rechecks current chat/route
admission after a held share download. Views only forward these resource intents.
External links offer preview and copy; unsupported URI schemes do not gain file
or share actions.

Read offset/limit are passive facts in the compact Read options row, alongside
its label, with no separate body or full-view/copy toolbar. Both are omitted
when not supplied. Unknown read arguments remain separately inspectable, and
Raw details keeps every exact argument. The charter's
[accepted activity family](DESIGN_SYSTEM.md#accepted-activity-detail-family)
owns the Read options spacing reference, compact control geometry, typography,
surfaces and completion presentation for every tool. There is no read-only
density branch. Large-text resource controls reflow below the readable path.
Exit codes and native image receipts add quiet context without replacing the
status or implying success.

Latest stock main inspected for these actions on 8 October 2026:
[`0240fa4a84123406a0e5e6e7262e5b772b43f0bd`](https://github.com/NousResearch/hermes-agent/commit/0240fa4a84123406a0e5e6e7262e5b772b43f0bd).
`hermes_cli/web_routers/files.py` retains `/api/fs/read-text` and
`/api/fs/download`, including profile-scoped reads and session-owned download
resolution. Existing client file readers and native sharing implement the UI;
no backend modifications are needed.

At the same stock commit, `SearchResult.to_dict` in
`tools/file_operations_common.py` supplies `total_count_is_lower_bound` when a
search is truncated; the active file-search tool invokes that serializer in
`tools/file_tools.py`. Display that qualification beside the reported match
count. A partial result must not present a lower-bound count as a complete total.
`test/tool_call_presentation_test.dart` guards true, false and absent qualifications.

`test/profile_tool_call_test.dart` guards preview/share forwarding, exact
punctuation-bearing paths, pending/retry behavior, icon-only controls and compact
read-option alignment in both themes and text sizes. `test/remote_file_saver_test.dart`
guards exact original bytes and held-download share admission after navigation or
owner disposal. These rendered and asynchronous properties require behavioral
checks; static source inspection cannot establish their outcomes.

The rich-render cases also compare each section's actual label/body positions
against the same card edge, top/bottom content framing and actual image left
edge, and require shared Completed wording, icon and neutral color across
code/read/edit/vision. They reproduce the previous green/neutral footer mismatch
and 10 dp extra centered-image gutter, and require all four content insets to
match the Read options reference, including actual compact toolbar height and
icon targets. Rendered geometry cannot be established by source linting;
the behavioral guard and visual family review are required together.


### Complete activity family

The accepted detail frame is shared by Tools, Tasks, live/saved Agents, reasoning
and Work, including goals, loops, heartbeats and background processes. The public
`ActivityDetailsCard`, `ActivityDetailContent`, `ActivityDetailSection`, `ActivityDetailStatus` and
`ActivityDetailAction` in `lib/core/widgets/tool_activity_details.dart` own one
surface, section padding, exact copy, local preview, full view and action geometry.
Views continue forwarding control intents to the captured supervision owner;
no second task, process or agent cache is introduced. Last-received/unavailable
agent output and process tail scope remain explicit. `GatewayProcessActivity`
keeps a bounded display command and its exact received source; output-tail data
is retained for copying/expansion instead of being clipped in the model.

Current stock main rechecked on 8 October 2026 remains
[`0240fa4a84123406a0e5e6e7262e5b772b43f0bd`](https://github.com/NousResearch/hermes-agent/commit/0240fa4a84123406a0e5e6e7262e5b772b43f0bd).
This refinement uses existing stock process, subagent, todo and session-control
observations/commands. Stock `tools/file_operations_common.py` and
`tools/file_tools.py` establish grouped search paths/lines/excerpts and independent
write/patch verification, lint status/output/message and semantic diagnostics.
Supplied web-source URLs retain exact link copy separately from excerpt copy.
Nothing adds a backend endpoint or derives an omitted execution result.

`test/activity_family_test.dart` reviews actual production Tasks, saved/live
Agents, Work, goals, reasoning, search, writes and web results in both themes at
390 dp/100% and 320 dp/200%. It checks shared surfaces, content framing and 32 dp
icon-only controls. Capture with `CAPTURE_ACTIVITY_FAMILY=true` and
`CAPTURE_FONT_DIR=/path/to/review/fonts` (Roboto, MaterialIcons, DejaVuSansMono);
images are written to ignored `build/activity-family/`. Review alongside the
code/read/edit/vision captures. Owner-level goal, process and subagent tests
retain confirmations, admission, rejection feedback and last-received data.

`test/profile_transcript_test.dart` and
`test/profile_disclosure_layout_test.dart` protect disclosure anchoring and
expansion through the shared frame, including 100%/200%/300% text. They target
the outer reasoning ListTile separately from its repeated section label, wait
for background Markdown completion before asserting prose, and inspect the
full received rich-text output inside a bounded scrolling pane.
`test/activity_family_test.dart` also guards source, diff, plain prose and
Markdown together: identical viewport caps, no Preview rows, independent scrolling,
exact copy, retained full view and four-sided framing across all activity families.
These are rendered and asynchronous properties requiring widget regressions;
source linting cannot establish tap targets, scroll positions or worker completion.
