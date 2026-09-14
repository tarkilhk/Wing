# Execution details, Find and Outputs

## Live execution

Tool activity upserts by server identity, with output capped at 12,000 characters per displayed result. Expanded details preserve useful output while the ordinary transcript stays compact. Todo/progress revisions are server-owned and read-only. Reasoning and timing appear only when Hermes supplies them.

String `review.summary` events appear as transient Activity notices, with a scoped limit of 20 and position-aware deduplication. Opening a notice shows its full text. It is not an approval or a persisted memory record.

System/control and agent-delivery presentation follows [Transcript projection](TRANSCRIPT_DISPLAY_TYPES.md). Raw history, row IDs and ordinal counts remain intact for actions and pagination.

## Find in chat

Start with the most recent 500 loaded messages. Search older loads additional server history, keeping existing results and retrying the same offset after a failure. Verify the history segment when compaction changes boundaries. A partial result set must not be presented as a complete archive search.

View in chat opens a bounded historical context with up to four nearby rows on either side and a highlighted result. This view is read-only; saved-message edits require the normal verified live history. Back to latest returns to the active conversation and its draft. Keep that action reachable even when a long result is expanded.

## Per-chat Outputs

Outputs indexes file references in recent history, initially 500 messages, with older batches available. It is not an authoritative filesystem inventory. Retain loaded results after a failed refresh and exclude passive cache paths from suggestions. Old references can return 404 if the server no longer exposes the file.

Direct Markdown links to supported result files use the same authenticated file client. Resolve them with the original connection/profile/chat, not a later selection. File errors distinguish unavailable/missing content from transient failures, offering Retry only where useful.

Use [Output viewers](OPENING_OUTPUT_FILES.md) for formats, download limits and sandbox boundaries. There is no general remote filesystem browser or global artifact library.
