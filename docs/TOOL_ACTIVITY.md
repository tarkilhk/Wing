# Readable tool activity

Open Activity in a conversation, then Tools. Every backend call has an individual
action row: a readable title, delivered target, explicit outcome and any available
duration. Expand a row to read its result. Vision calls show their exact
`image_url` input using the existing bounded image preview and full-screen viewer,
followed by the question and returned analysis. Raw details exposes selectable,
copyable tool identity, inputs and output without client payload truncation.
Tasks, Agents, Work and Thinking retain their existing visibility and selection;
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
  invents transcript rows. After restarting, absent backend timing stays absent.

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

Inspect production widgets at 360 dp with ordinary and enlarged text in both
themes, including expanded vision and raw details. Store captures under ignored
`build/` or outside the repository, as required by `docs/PERFORMANCE.md`.

## Tasks and Agents

The Tasks tab retains backend order and parent indentation. Full task text stays
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
