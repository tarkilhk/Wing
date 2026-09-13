# Recovering side and background tasks

Owner correction, 2026-09-12: **No Hermes backend modifications.** Any patch
contracts or deployment instructions described below are rejected experiments,
retained only as research. They were never deployed. Use existing Hermes APIs;
features requiring those invented contracts are deferred, not delivered. Do not
configure a new Hermes sender or deploy patches based on this document.

## Current behavior

Android displays live side-question and background-task events. A real `/btw`
round trip passed QA. Cold recovery and discovery of unseen child-only work
remain unavailable through the verified stock-server contract. In live QA,
`session.active_list` omitted the idle parent while its child was running and
provided no `side_tasks_running` count. Android cannot infer an authoritative
cross-profile list from events it never received.

The client can parse optional task snapshots, but those parsers do not establish
server support. Current evidence and limits are recorded in
[the QA sweep](QA_SWEEP_2026-09-13.md).

## Historical proposal, rejected and never deployed

The following describes the 2.30.0 proposal, not delivered backend behavior.
The proposed D11/Q12/T14 recovery would restore `/btw`, `/bg` and `/background`
cards from server snapshots when a chat resumed or received session info,
while keeping the composer available during background-only work.

Backend patch 0006 supplies `side_tasks` with `retention: live_session` and task
IDs, kinds, prompts, status and available results. Android replaces the displayed
list with that snapshot. An explicit empty list clears it; a partial session-info
update without this field preserves the current cards. Failed tasks and shortened
prompts/results are labeled. No task list is persisted on the phone.

The live-session list keeps all running work and a bounded set of recent results.
Prompt text is limited to 4,096 characters and results to 65,536 characters, with
explicit truncation flags. Running tasks prevent the owning live session from
being reaped while they finish. Closing a session or restarting the server loses
this in-memory task list; the contract does not promise durable task recovery.

`session.active_list` includes `side_tasks_running`. Activity uses that server
count to show chats with background work even when their foreground turn is idle.
Each chat still occupies one row across All and Running filters. A foreground
request for input keeps its Needs input label. No local pending-card count stands
in for the authoritative server count.

Patch 0006 targets Hermes `8d79c2ff57bba4b07e5b37ed90387b16541aef53` and
must be deployed for recovery and unopened-chat background discovery. This adds
neither a separate task database nor cancellation/child-chat links that Hermes
does not provide. Existing live command/result handling remains available.

The tests cover authoritative replacement/clearing, partial updates, additive
metadata, error/truncation labels and Activity filters with idle foreground work.
Release results and live acceptance status stay in the
[delivery sequence](DELIVERY_SEQUENCE.md).
