# Tool activity

Open **Activity** in a conversation to inspect Timeline, Tasks, Agents, and Work.
Expand a row to see what was requested and what Hermes returned. Available
controls use icons with accessible labels and tooltips. Long content can open
in a fuller reader; reusable code, commands, and output offer copying and wrap
controls. Raw details retains received inputs and results, including fields
not summarized in the compact view.

## Timeline and reasoning

Timeline shows individual tool calls and reasoning in their received order.
Compact rows show an action and input summary; warnings and failures remain
visible. Expand for details, source references, received images, and available
results. Opening a received result does not rerun its tool. Completion means the
call finished; check its output and any error before assuming success.

Reasoning appears only when the model or server supplies readable text. Some
providers supply a short preview or do not save reasoning. Live reasoning and
saved history may therefore differ. Wing does not reconstruct missing text or
display encrypted reasoning.

File and web results retain their supplied locations. A filename can be shortened
on screen; its popup shows the full location and file actions use that original
target. A search receipt with an unreliable location remains readable in Raw
but does not gain misleading file actions. See
[Output viewers and downloads](OPENING_OUTPUT_FILES.md).

## Approximate reply time

A saved reply's collapsed Activity header can show "Used 11 tools · 1m 24s".
This is the interval between the original sent prompt and final saved answer,
including thinking and tool work. It is not the sum of tool durations. Reopening
Wing does not change an interval available in saved history. Missing or invalid
timestamps, an unsaved reply, or an unloaded original prompt can leave it absent.

Individual tools can show approximate elapsed time while running. A measured
completion duration replaces that estimate when received. Historical timing may
be unavailable if Wing never received it and Hermes no longer retains it. Wing
keeps received measurements locally; a missing measurement is not guessed from
message timestamps. These times describe work, not a guarantee of success.

## Tasks, Agents, and Work

Tasks show the reported checklist, order, nesting, and states. Older Activity
sections retain their own reported task snapshots rather than today's list.
Agents show received delegation goals, status, and available output. Live agents
can show approximate elapsed time; saved dispatches are historical and do not
start timers or offer live controls. See [Subagent supervision](SUBAGENT_SUPERVISION.md)
for steering, interruption, and unavailable output.

Work shows the chat's goals, recurring work, and processes. Its actions are the
same controls available from the chat menu. See [Session controls](SESSION_CONTROLS.md).
Approvals and questions remain separate from tool disclosures.

## Conversation compression

"Summarizing conversation…" above the composer means Hermes is compressing the
conversation. It is a status observation, not a new message. Input requests and
recovery notices take priority. The label clears when summarization ends or
normal work resumes.

## Captured skill reading

Open a received skill to read its instructions without rerunning it. The reader
supports raw/formatted views, Contents, previous/next navigation, and available
reference documents. Formatted viewing focuses on the instructions; Raw retains
the complete received content, including declarations and any bundle context.
The reader preserves the received instructions rather than replacing them with
a newer version. Optional metadata or activity failures do not prevent reading.

Reference documents appear when Hermes provides a valid file listing. Their
content may carry a truncation notice. Available profile activity counts and
read-request counts describe different things; missing records stay unknown.
