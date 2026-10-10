# Activity field decisions

Wing targets unmodified upstream Hermes. This review inspected current main
[`25a71a744cb9ef06950a91638e6229b4f808d461`](https://github.com/NousResearch/hermes-agent/commit/25a71a744cb9ef06950a91638e6229b4f808d461)
on 8 October 2026. The catalog below accounts for all 32 Wing activity identities;
26 are registered in this stock version. Two additional current identities,
`tool_describe` and `cronjob_manage`, have dedicated projections. A display
caption is not a backend contract.

The [Studio charter](../DESIGN_SYSTEM.md#user-value-first-activity) owns visual
and action policy. This document owns tool-specific field decisions. Exact
inputs and receipts remain in Raw details, including fields omitted from the
main card. An absent field stays unknown; a supplied false, zero or empty authored
string is assessed according to that tool's meaning.

## Selection and ownership

`ToolActivityDetails.project` is the single pure selection interface for live
and saved tool activities. Private family projectors select semantic payloads,
quiet header facts, useful resources and reported outcome qualifications. They
perform no I/O and preserve exact received clipboard scopes. Shared widgets own
framing, text layout, overflow, scrolling and icon order. Captured resource owners
retain authenticated loading, viewing and sharing; projectors never rerun a tool.

Compare two arrangements when adding a tool: field-by-field cards versus a
curated account of intent, payload and result. Choose the latter when it removes
repeated meaning without obscuring achievement or recovery. Additional dedicated
logic earns its place through different field semantics, not different styling.

Each row below gives the main signal, supplied title context, outcome limits and
reusable scope. Fields not selected here stay Raw. Routine success booleans,
implementation identifiers, serialized schemas, echoed values and bookkeeping
stay Raw unless the row identifies a meaningful exception. A structured unknown
response is one cohesive observation, never a toolbar for every key.

## Files

Sources: [`file_tools.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/file_tools.py),
[`file_operations_common.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/file_operations_common.py),
[`file_operations_search.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/file_operations_search.py).

| Identity | Main signal and meaningful receipt | Quiet context and qualifications | Useful scope |
| --- | --- | --- | --- |
| `read_file` | Requested file and received `content`; rendered Markdown for Markdown files, literal source otherwise. Preserve numbered receipt separately from formatted display. | Supplied offset/limit in resource title. Reported total lines, next offset, partial/clipped range, extraction and conflict warnings. Missing/binary/deduplicated/refused reads retain their real explanation. | One resource header eye/share and exact received content copy; no repeated body actions. A file viewer reads current bytes, while copy retains the historical receipt. |
| `write_file` | Requested complete `content`, actual destination and reported outcome. The request is not a returned file or diff. | Actual `verified:true` means content hash matched; omission means unknown. Failed syntax or semantic findings stay visible. Skipped lint, dirs_created and duplicate resolved_path stay Raw. | Exact authored content copy once; resource eye/share requires a receipt with a nonnegative integer `bytes_written` and no reported failure. A zero-byte successful write qualifies; pending or bookkeeping-only paths stay passive. |
| `patch` | Find/Replace or the actual requested patch; reported diff separately. Actual created/deleted resources and actionable diagnostics. | Supplied mode/replace_all. `no_change` takes precedence over bookkeeping paths. Apply failures may retain partial changes. No synthetic verification or replacement count. | Distinct exact Find, Replace, requested patch and received diff scopes; destination actions require `success:true`, no failure, no `no_change` and no deletion. Explicitly created resources surviving a partial failure remain actionable. Deleted targets stay passive. |
| `search_files` | Pattern and scope; grouped returned excerpts, file list or per-file counts according to actual result mode. | Supplied target/filter/context/limit/offset/order/output_mode. Qualify reported count semantics, lower bounds, omitted paths, timeouts and partial results. matches_format is Raw. | One excerpt copy/resource header per meaningful group. Directory/file lists of unknown kind stay passive; no individual path/count copies. |
| `edit_file` | No current stock registry/schema. | Exact Raw and restrained unknown receipt. | No alias to patch/write. |
| `list_files` | No current stock registry/schema. | Exact Raw and restrained unknown receipt. | No alias to search_files. |

Dense search text is decoded only through the supplied stock grammar and valid
path/line rows. Context rows are not necessarily hits. Counts may precede omitted
path filtering; they do not establish the exact number of visible global matches.
A malformed dense receipt remains accessible without fabricated grouping.

The filename/locator follow-up inspected current stock
[`38880bd2f1e90dbc9a1aeec03af62539ee64719a`](https://github.com/NousResearch/hermes-agent/commit/38880bd2f1e90dbc9a1aeec03af62539ee64719a)
on 8 October; its search parser and common receipt formatter are unchanged from
the review above. The context parser takes the rightmost `-<number>-` separator,
including one inside a date in source text. A returned context path formed as
the supplied scope followed by a numeric context separator contradicts that
scope; it cannot identify a file inside it. Wing keeps the exact malformed row
Raw, qualifies unreliable context and renders valid excerpts. It does not infer
a corrected filename/line or offer file I/O for that row.

## Source coloring, 10 October 2026

Inspected latest stock upstream main
[`5ba559c9e4b1c8397df7788e319ab634144ca728`](https://github.com/NousResearch/hermes-agent/commit/5ba559c9e4b1c8397df7788e319ab634144ca728):
`tui_gateway/tool_progress.py`, `tui_gateway/session_history.py`,
`hermes_cli/web_routers/files.py`, `tools/code_execution_tool.py`,
`tools/browser_use_cli.py`, `tools/terminal_tool.py` and `tools/file_tools.py`.
Live `tool.start.args` / `tool.complete.args,result` and saved call inputs/results
retain their existing acquisition and exact identity owners. No server change
or new endpoint is required.

| Family / received field | User value and placement | Grammar / action scope |
| --- | --- | --- |
| Chat fenced source / fence info | Read generated code in its existing source block | Supplied language selects a built-in grammar; exact code copy and existing wrap/preview actions |
| `execute_code.code`, `browser_exec.code` | Reusable requested source in main Code payload | Stock schemas declare Python; exact code selection/copy and existing overflow viewer |
| `terminal.command`, process `commandSource` | Reusable requested shell source in main Command payload | Bash coloring convention; the grammar is visual and does not assert the runtime shell/OS. Exact command selection/copy; existing overflow viewer |
| `read_file.content` + returned/requested path | Read the received source excerpt in the existing resource frame | File extension selects grammar. Parse without stock `N\|` decoration, then restore every literal prefix for selection/copy. Binary/extracted documents have no source grammar |
| `write_file.content`, `patch.old_string,new_string` + requested path | Read authored content / distinct Find and Replace source | Requested file extension selects grammar; exact independent copy scopes. Supplied diffs retain semantic +/- coloring |
| `/api/fs/read-text`: `text,language` | Read actual current file preview through existing output owner | Supplied language selects grammar; stock `shell` maps to Bash source, JSX/TSX use registered grammar identifiers |
| Console stdout/stderr, output tails, diagnostic text, unknown tool text | Read exact received evidence | No code inference from ordinary output; retain natural text and existing status/diff semantics |
| Empty/short/overflowing/partial/failed payloads | Preserve their existing readable states and received completeness qualifiers | No new actions or frame. Syntax colors never invent success, completeness, resources or a language label |

The chosen arrangement colors source inside the existing shared renderer; a
separate editor/preview panel would duplicate framing and copy/wrap controls.
No extra language heading or selector is introduced. Unidentified source stays
literal. Live Markdown fences stay literal until the response finishes and the
fence closes, avoiding grammar work and color churn during streaming.
Tokenization runs off-thread, coalesces changing receipts and discards stale
results. Sources over 8 Ki UTF-16 code units or 200 lines, or producing more than
768 spans, retain full literal content without rich syntax layout. Character
and line budgets reject work before spawning an isolate; adjacent equivalent
tokens are coalesced. The mounted renderer reuses tokens and span trees across
unchanged parent/selection rebuilds, refreshes colors for palette changes, and
retains its state across wrap toggles. There is no persistent source cache.
Palette contrast is checked against both Studio content surfaces; source colors do not replace warnings, errors or diffs.

`test/source_highlighting_test.dart` covers language evidence, exact receipt bytes,
multiline grammars, completion-only live coloring, admission/span bounds,
streamed replacement/disposal, span reuse, theme/wrap/copy, contrast and
chat/execution/file renders at 390 dp/100% and 320 dp/200% in both themes.
Existing file/action/Markdown/output-viewer tests cover scoped resource controls
and recovery. These are stock-contract fixtures, not a live server or device run.

## Execution and images

Sources: [`terminal_tool.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/terminal_tool.py),
[`code_execution_tool.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/code_execution_tool.py),
[`browser_use_cli.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/browser_use_cli.py),
[`image_generation_tool.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/image_generation_tool.py),
[`vision_tools.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/vision_tools.py).

| Identity | Main signal and meaningful receipt | Quiet context and qualifications | Useful scope |
| --- | --- | --- | --- |
| `terminal` | Exact command and literal console; explicit refusal/recovery. | Supplied directory/timeout/background/notification intent. Background spawn exit0 means launch only; yield means continuing. Reported informational nonzero meanings differ from failure. Spill/truncation, changed cwd and infrastructure loss remain explicit. Pending approval remains with the approval owner. | Exact command/output copies. One supplied full-output resource eye when present; no option/session/PID copies. |
| `execute_code` | Exact code and console. Reported helper tool errors remain visible even if the outer script succeeded. | Supplied reset intent. Actual exit/status, partial stdout and kernel state loss; server duration does not replace gateway timing. | Exact code/output copies and useful supplied spill resource. |
| `browser_exec` | Exact code and actual CLI console/diagnostics; actual screenshot. | Supplied session/timeout/local intent. Native text_summary contains the ordinary result JSON, not a second result. CLI success does not establish the user's browser goal. | Distinct code/output/diagnostic copies; screenshot eye/share with the original resource owner, or actual embedded pixels. |
| `image_generate` | Requested prompt and actual generated resources, including additional images; distinct revised prompt. | Supplied creative controls. Actual model/provider/pixels when received; storage/dropped-reference warnings affect achievement. n is requested count, not returned images. | Exact meaningful prompt copies; one eye/share per actual image. No path/base64 copy. |
| `vision_analyze` | Actual question, image and auxiliary analysis if received. Native attachment is a receipt, never invented analysis. | Supplied crop and actual scale/crop note; already-attached is distinct from a new load. meta.image_url is truncated and cannot be a locator. | Exact question/analysis copies; one image viewer. Crops use actual received pixels when available. |

Embedded image parts are admitted through a bounded tool-receipt image loader.
Other locators keep conversation admission and the captured profile/session
owner. A preview error offers retry; bytes or unsupported locators never gain an
imaginary remote-file sharing capability.

## Browser, web and desktop preview

Sources: [`browser_tool.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/browser_tool.py),
[`web_tools.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/web_tools.py),
[`preview_tool.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/preview_tool.py),
[`drive_preview_tool.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/drive_preview_tool.py).

| Identity | Main signal and meaningful receipt | Quiet context and qualifications | Useful scope |
| --- | --- | --- | --- |
| `browser_navigate` | Requested URL and actual returned page/snapshot. | Redirected result URL distinct from requested URL. Actual title/element count and blocking/fallback warning. | One actual source eye, exact returned snapshot copy. No duplicate URL body. |
| `browser_snapshot` | Literal returned accessibility tree and pending dialogs. | Supplied full flag, actual element count, explicit partial tree/frame inventory and stored-file recovery. No borrowed page URL. | Exact snapshot copy; overflow eye or actual recoverable stored resource. |
| `browser_click` | Requested ref and actual clicked acknowledgement. | Actual returned destination/warnings when present. A click does not prove a form saved. | Actual useful resource eye; short acknowledgement is passive. |
| `browser_type` | Requested literal text and any distinct returned/redacted text. | Requested/returned element; explicit empty text means clearing. No inferred submit. | Copy each distinct meaningful supplied text once; identical echo remains quiet. |
| `web_search` | Query and returned sources with title/host/excerpt. | Supplied limit, actual partial/provider failures and search warnings. | One source eye and exact excerpt copy; empty excerpt has no copy. |
| `web_extract` | Requested sources and actual Markdown extracts or per-page error. | Supplied character limit; partial content and explicit 404 retain uncertainty. Mixed success keeps useful pages. | Source header eye/exact excerpt copy once; no repeated URL copies. |
| `desktop_preview` | Open/close acknowledgement or actual returned read text. | Supplied action/range; actual title/tab/range/total and partial window. Acknowledgement is not rendered-page proof. | Actual resource eye and exact read payload copy; small ack passive. |
| `drive_preview` | Actual action, element inventory or sparse delta. | Supplied target/limit/tab/submit intent; received disabled/cleared/checked states, navigating warning and result note. No reconstructed baseline from delta. | Useful actual resource eye; returned text copy only. Generated element summaries are passive, exact structured receipt stays Raw. |
| `browser_fill` | No current stock registry/schema. | Exact Raw and restrained unknown receipt. | No alias to browser_type. |
| `browser_take_screenshot` | No current stock registry/schema. | Exact Raw and restrained unknown receipt. | No invented screenshot or browser_exec alias. |

## State, skills and delegation

Sources: [`memory_tool.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/memory_tool.py),
[`skills_tool.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/skills_tool.py),
[`todo_tool.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/todo_tool.py),
[`delegate_task_tool.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/delegate_tool.py),
[`cronjob_tools.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/cronjob_tools.py),
[`session_search_tool.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/session_search_tool.py).

| Identity | Main signal and meaningful receipt | Quiet context and qualifications | Useful scope |
| --- | --- | --- | --- |
| `memory` | Requested whole entry/find and actual replaced/removed entry or useful matching/current entries. | Supplied store/action; reported capacity/count and staging/refusal/recovery. Operation count is not content-change count. | Exact authored/returned entry copy; passive bookkeeping. |
| `skill_view` | Main document card: received skill name and description; absent description uses bounded actual instructions. The eye opens the full received Markdown, omitting front matter from prose while preserving exact raw/copy text. Linked support files retain their source/document rendering. | Supplied tags and typed author/version/license declarations appear only in the viewer. Supplied file selection and received setup/unavailable/binary/unchanged context remain explicit; missing fields stay absent. | One exact instruction copy and received-document eye; sharing requires an actual supplied source resource. No file, edit authority or active state invented from the name. |
| `skill_manage` | Supplied skill name heads each meaningful operation; requested content/find/replacement and Result receipt. | Supplied action/path, actual operation/error count and partial failure. Success booleans, echoed action/name and routine ack remain quiet/Raw. | Genuine authored content copy; short result has no text viewer/copy. |
| `todo_list` | Requested task work and actual returned tasks with status/parent context. | Supplied mode and reported counts; Tasks remains read-only evidence. | Authored task content if independently useful; no synthetic checkbox controls/status copies. |
| `delegate_task` | Actual tasks[] goals/instructions and actual child result. | Supplied task model/limits; dispatch != completed work. Reported truncation, max_iterations, schema invalid/note/errors and absent terminal output stay qualified. | Exact authored task and meaningful returned result copies. Lifecycle controls remain with Agents owner. |
| `cronjob` | No current stock registry/schema. | Exact Raw and restrained unknown receipt. | No alias to cronjob_manage. |
| `session_search` | Actual index/search/read/resolve result: titles/summary/received transcript or selected reference. | Supplied action/query/range/filter; reported partial/continuation context. Shared read-session identity appears once; messages retain their role/anchor qualifications. Session refs stay identifiers, not fabricated web links. | Exact useful received excerpt/transcript copy; passive identities/counts. |
| `cronjob_manage` (current additional identity) | Requested scheduled prompt/script and actual listed/created/updated/run receipt. | Supplied schedule/name/action; actual enabled/paused state, execution and delivery failures. Manual/background dispatch does not establish job completion or delivered message. | Exact authored prompt/script; actual meaningful execution output copy. Existing Scheduled tasks owns mutation controls. |

## Discovery, connectors and questions

Sources: [`tool_search.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/tool_search.py),
[`tool_search_validation.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/tool_search_validation.py),
[`clarify_tool.py`](https://github.com/NousResearch/hermes-agent/blob/25a71a744cb9ef06950a91638e6229b4f808d461/tools/clarify_tool.py).

| Identity | Main signal and meaningful receipt | Quiet context and qualifications | Useful scope |
| --- | --- | --- | --- |
| `tool_get` | No current stock registry/schema. | Exact Raw and restrained unknown receipt. | No alias to tool_describe. |
| `tool_search` | Requested capability queries and selected tool identities/descriptions. | Supplied limit/source and actual partial availability/errors. Loaded schema and registries stay Raw. | Reusable query; discovered descriptions passive, no copied schema plumbing. |
| `tool_call` | Each actual invocation name and its opaque response or per-entry error. | Wrapper routing counts describe dispatch, not domain success. Keep structured provider response cohesive and exact in Raw; never infer semantics from nested status names. | Actual reusable returned text copy; opaque generated summaries have no copy. |
| `clarify` | Actual questions/choices and retained answers/skips/unanswered states. | Supplied multi-select and reported wait outcome; canceled/timed-out calls can retain answers. Pending interaction remains with questions owner. | Exact meaningful answer text where reusable; no recreated answering controls. |
| `tool_describe` (current additional identity) | Requested names and actual capability descriptions. | Supplied source, per-name absence/errors, partial discovery. Parameters/schema/loaded internals stay Raw. | Descriptions readable; no metadata/schema toolbars. |

## Non-tool families

Tasks, reasoning, live/saved Agents, goals/contracts/criteria, recurring work and
processes consume the same shared framing/action policy. Task/status/context
lists are passive. Meaningful authored reasoning, goals, prompts, commands and
received output earn an exact copy scope. Saved Agents retain the requested task
and actual terminal status even without output; a completed wrapper retains
reported truncation and failed result validation. A process launch or exited
process without a supplied exit code does not acquire a successful exit. Existing
steer, interrupt, refresh, retry and scheduling ownership stays intact.

### Native reasoning fields and actions

Verified native reasoning contract: upstream `aa74e184ea779994af642ab4f888e10a95415d90`.

| Field or action | User signal and placement | Scope and eligibility |
| --- | --- | --- |
| Delta or available text | Compact one-line received-text preview, with exact authored Markdown in expanded main content | Empty/absent reasoning produces no row; whitespace deltas preserve word boundaries; long text scrolls in the shared viewport |
| Available text after a streamed run | Retained separate receipt in Raw details; streamed main text remains intact | No inferred truncation or completeness; exact receipt can be copied/opened under the same payload rules |
| Native event source | Raw details identifies the received event type | Passive; no copy/view control for routing metadata |
| Verbose hint, session ID and event sequence | Transport/presentation context; no additional main-card field | No operational user action; sequence is not an insight count |
| Saved string reasoning and typed readable summary/text parts | Reasoning at the saved assistant message position | Ignore opaque/encrypted parts and signatures; absent readable text stays absent |
| Expand | Shared compact Reasoning/Thinking row with the full received body | No extra panel or footer; empty rows omitted |
| Reasoning glyph | Shared circuit-brain from the reasoning selector distinguishes reasoning from Hindsight memory's outlined head | Same glyph for active, sealed and saved reasoning; the title carries its phase |
| Copy | Icon-only exact received reasoning text | One scoped payload copy; no derived summary copy |
| Eye | Icon-only existing fuller text viewer | Actual layout overflow only; short prose has no eye |
| Timing, counts, wrap and share | No native reasoning duration/insight count/resource | Omitted; prose reflows and has no literal wrapping toggle |

Live rows and saved message attachments have independent native sources. Neither
requires a persistent client timeline or reconstruction of missing live events.

## Verification

Family projector regressions exercise exact public observations and selection.
Source-shaped fixtures are sanitized examples from the pinned contract, not
claims that stock tools were executed or private conversation captures. Render
checks cover all supported identities, restrained unsupported identities and
non-tool families in light/dark at 390 dp/100% and 320 dp/200%, with short/long,
empty, failed and partial variants. Inspect those actual renders together and
check useful-only icon eligibility, exact clipboard scopes, neutral completion,
all four visible insets and bounded scrolling before declaring the family ready.
