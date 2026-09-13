# Execution, Find and Outputs — 2026-09-12

This delivery implements the active D14 reading paths, D18 Find, and the first D16/D17 output flows. It uses the existing gateway and HTTP client, tool/reasoning parsers, file transport, Markdown and Android share dependencies.

## Execution details

Live tool calls now update by server tool ID, with expandable arguments/results, progress, errors and server-reported duration. Generating is a name-only status. Raw payload display is capped at 12,000 characters. A successful server history refresh removes completed live rows to avoid showing the same call twice beside stored tool results.

Server todo snapshots populate a read-only task panel. The client recognizes pending, in-progress, completed and cancelled statuses, preserves simple parent indentation and rejects older revisions. Create/resume can restore `todo_state`; no local todo database or task editor was added.

Reasoning events feed a collapsed disclosure. Historical reasoning is displayed when the server returns one of the verified string fields. The app does not invent timings or reconstruct reasoning absent from history. General tool output remains plain selectable text; there is no terminal, Git client or custom UI for each tool.

## Find in chat

The chat actions menu contains Find, Outputs and Refresh. Find filters loaded
server history as the query changes, with expandable selectable matches.
Closing the sheet preserves the transcript's reading position. Failure and
retry remain visible. The 2.24.1 behavior and remaining navigation work are
described below.

The original implementation used an oldest-first complete-history loader and
stopped at 10,000 rows or 32 MiB of JSON characters. The 2.24.1 follow-up below
replaces it with explicit recent-first batches shared with Outputs.

### Paged Find follow-up, 2.24.1

Find opens after loading the most recent 500 saved messages. Typing searches
that loaded history; **Search older messages** adds the next batch without
clearing the query or prior results. Counts and empty states identify partial
history until the server reports its end. Matching messages remain expandable
and selectable, including matches beyond the previous 100-result display cap.

Failed older requests retain the loaded messages and retry the same offset.
Closing the sheet discards this temporary search view. There is no persistent
transcript, new search service or automatic scan of the complete chat.

The shared saved-page loader uses the history segment already identified by
Hermes when opening the chat. This matters after server-side compression,
which can change the segment ID while the durable chat identity stays the same.
An unrelated returned segment is still rejected. Outputs uses the same loader.

The exact pre-fix size error was reproduced through the actual chat-menu Find
entry against a 10,000-message fixture. Ten focused checks pass, including
overlap deduplication, retries, ownership and narrow layout with large text and
the keyboard visible. The full suite passes 1,176 tests with four opt-in skips;
analysis is clean. One additional loaded-results/error/keyboard layout check
also passes. Signed Personal 2.24.1 / 21742 passed native compilation and
certificate/package checks; installation awaits a new wireless-debugging
endpoint after the phone refused the last address. Navigation from a match to
its message remains the next selected D18 portion.

### Find result navigation, 2.26.0

The selected C03/T11 follow-up adds **View in chat** to each Find match. The
result retains its original fetched history and row ID, including older batches.
The chat displays the matched message with up to four saved rows on either side,
using the existing message and tool renderers. Matching tool disclosures open
automatically and the match is highlighted. **Back to latest** stays visible and
returns to the normal conversation. This view supports reading, copying and media
access; saved-message editing and branching remain in the normal transcript.

This is disposable reading state. It does not replace the chat's current history,
change its pagination, save a transcript or route through a different profile.
Changing chat or refreshing history invalidates a stale selection. All 22 focused
checks passed, including older results, stale selection, tool expansion and
320-pixel layouts at 200% text size. A regression with long preceding messages
reproduced an offscreen match before replacing the nearby view's lazy list with
an eager, bounded column; the selected tool output is now verified visible.
Full suite: 1,191 passed, four opt-in skips;
analyzer clean. Signed Personal 2.26.0 / 21772 passed native compilation and
certificate/package checks. Phone installation remains deferred while the owner
is away from home.

## Direct file links and review summaries, 2.31.0

F03/F06/T06 extends existing message links to explicit remote file targets.
Relative paths, absolute paths and file references open through the same
authenticated file readers and viewers used by Outputs. Requests keep their
original profile and saved chat. Web links continue through the browser preview;
unsupported URI schemes are rejected. This does not add a filesystem browser or
scan a conversation before opening its linked file.

T14 displays the existing `review.summary` event as a typed `review:` system row
in the conversation. A memory icon labelled Hermes review opens the full received
text in a scrollable sheet. As newer messages arrive, the row folds into Activity
alongside adjacent tool results instead of following the conversation as a large
card. Opening the sheet does not approve or discard pending memory changes.

Only string text is accepted, duplicates are suppressed, and the newest 20
reviews remain in memory. Same-runtime history refresh retains their positions
relative to surrounding messages without counting them in server paging offsets.
Runtime replacement or app restart clears them. The gateway sends summary text,
not a skill-file diff; no recovery API or local review database is introduced.

Desktop source inspected at `e16f686706b1e0d5334fd1ae82190058d2a19694` uses the
same typed transcript row in `apps/desktop/src/app/session/hooks/use-message-stream/
gateway-event/status.ts` and a memory icon in
`apps/desktop/src/components/assistant-ui/thread/system-message.tsx`. Android's
detail sheet and Activity folding adapt that behavior to the owner's phone UX.

The T12/R08/R09 attention control also recognizes live sensitive requests while
reading older history. Input needed returns to the latest content without
answering or approving the request.

## Per-chat Outputs

Outputs follows Desktop's transcript-derived approach. It finds assistant-delivered MEDIA tags, links/images and qualified paths, plus explicit producer-tool output fields. It recognizes common documents, archives and media; explicit references may use relative filenames. Passive tool cache/source paths are excluded where possible. Candidates are deduplicated within the one selected chat and remain disposable.

This is a useful index of references, not an authoritative server output catalog: it can miss silent outputs or retain a path whose file was removed. The UI describes that limit. It does not scan other chats or expose a filesystem browser.

File reads and downloads include the original `profile` and durable `session_id` on the authenticated host connection. Downloads enforce a 32 MiB limit against declared and streamed size. The client uses the modern download route, strips server filenames to decoded basenames, writes user-requested files to temporary staging, and hands actual file bytes to Android's share/save flow. Credentials stay on the existing authentication path.

Images use the zoomable preview, including authenticated bytes and embedded data images. Text/code use the existing selectable code renderer with a shortened-preview indication when Hermes reports truncation. Binary formats can be saved/shared for another Android app to open. Later deliveries add PDF pages, native audio/video playback, Markdown/source, SVG and web previews; 2.24 adds downloaded interactive HTML. See [opening files](OPENING_OUTPUT_FILES.md) and [web previews](MARKDOWN_AND_WEB_PREVIEWS.md).

## Large-chat Outputs fix — 2.24.0

The owner's screenshot exposed a real loading failure: Outputs used the same
complete-history loader as Find and displayed its size-limit error, with Retry
repeating the same request. The exact error was reproduced through the real
chat menu against a 10,000-message server fixture before changing the code.

Outputs now requests the most recent 500 saved messages and displays their file
and link references immediately. **Load older outputs** fetches the next batch
from the same host, profile and session. Each batch contributes deduplicated
references; raw transcript pages are discarded and no history is persisted.
If the recent batch contains no outputs, the screen explains that older history
can be searched with the same button.

A failed batch preserves the files already listed and **Try again** retries
that batch. Initial failure also offers **Back to chat**. Refresh replaces the
list only after the new first batch succeeds. This removes the total-history
size gate from Outputs while retaining bounded individual requests and the
existing authenticated file actions.

The regression verifies recent-first display with one initial request, recovery
from a failed older batch, correct profile scope, the oldest file in the large
chat, and completion without duplicate references. Existing preview/delivery
and history checks also pass. Live verification of the owner's particular chat
remains separate from this synthetic reproduction.

Release verification: 1,173 full-suite passes, four opt-in skips, clean analyzer
and a separate pagination/retry review. Signed Personal 2.24.0 / 21732 passed
native compilation and certificate/package checks, installed in place at the
owner's wireless endpoint and launched (process 31824). Phone checks establish
installed version and launch, not the contents of the owner's private chat.

## Verification and remaining work

Release source: Personal `2.2.0+2149`, ARM64 code `21492`. Analyzer clean; full suite 970 passed, four opt-in skips. Final build/phone results are recorded in the delivery sequence. Focused tests cover event ownership, tool upserts, todo revisions, reasoning, saved-history pagination and failure, Find expansion/count/retry, output extraction, authenticated scope, filenames, byte limits, preview navigation and actual delivered bytes. Output layouts are checked at 320 pixels and 200% text size.

Live behavior on the owner's gateway still needs verification. The pinned Desktop source establishes request shapes, not whether the deployed server exposes them or how it resolves every relative/tilde path. No Firebase integration, broad administration, global output registry or extra backend compatibility path was added.
