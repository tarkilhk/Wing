# Conversation foundations — 2026-09-11

Current caveat: a normal send interrupted by process death before acknowledgement can
restore text without an uncertainty warning. Check server history before resending.
See [Known limitations](KNOWN_LIMITATIONS.md). The following delivery evidence is dated.

First feature delivery after the app shell: D01–D04, plus the small D06 approval improvements and D08 device switches. Full Activity and sensitive requests remain separate work. The owner authorized implementation in priority order, inexpensive agents for bounded tasks, and regular commits and pushes to `main`.

## Changes

- Composer text and staged attachment references are saved per verified connection identity, profile and durable session ID. Staged files use application-support storage rather than temporary storage. Missing files retain the text and show a recovery message. Deleting a chat removes its saved draft.
- Accepted sends clear the submitted draft; text typed while the acknowledgement is pending remains. Rapid Send taps submit once. Lost acknowledgements retain the draft with an uncertainty message and never trigger automatic resubmission. A generic server `running` flag is insufficient evidence to discard a draft.
- Reopening an already loaded chat refreshes its server execution and pending-input state as well as history. A submission awaiting acknowledgement keeps its current transport state. Existing reconnect behavior remains in use.
- Model selection groups by exact technical-provider route, with expandable sections and search. Duplicate model IDs on different routes remain distinct. Removed the unused local model-override store; server session configuration and `session.info` events supply current choices.
- `/yolo` reads the current boolean from session information, then uses session-scoped `config.set`. An unknown state is refreshed with the existing resume call. The response's effective value controls the confirmation. Global defaults are not changed.
- Approval controls reuse the existing request parser and render the scopes offered by Hermes. Responses include the request ID when supplied. A late acknowledgement cannot clear a newer request. Failed responses retain the request for retry. Existing batched clarification behavior is preserved.
- App settings have independent device switches for completion and attention alerts. Existing notification permission and original-session tap routing remain. The UI states that local alerts require an active connection; FCM is later work.

## Contract evidence and limits

Desktop evidence is pinned to `d15ed4445207dda418b984e8bda0f68f48b8c6f3` in NousResearch/hermes-agent:

- [`lib/yolo-session.ts`](https://github.com/NousResearch/hermes-agent/blob/d15ed4445207dda418b984e8bda0f68f48b8c6f3/apps/desktop/src/lib/yolo-session.ts): session write and acknowledged `value`; global scope is a separate operation.
- [`types/hermes.ts`](https://github.com/NousResearch/hermes-agent/blob/d15ed4445207dda418b984e8bda0f68f48b8c6f3/apps/desktop/src/types/hermes.ts): session information and resume pending approval/clarification fields.
- [`tool/approval.tsx`](https://github.com/NousResearch/hermes-agent/blob/d15ed4445207dda418b984e8bda0f68f48b8c6f3/apps/desktop/src/components/assistant-ui/tool/approval.tsx): advertised scopes and response targeting.

The local Desktop gateway used by earlier integration tests was not running during this delivery. Source checks and fixtures are not evidence of deployed-backend compatibility. Keep live session YOLO, cross-client configuration, and phone restart/draft checks outstanding until exercised against the owner's server. No model turn was submitted for these source and unit checks.

## Verification

Static analysis is clean. The full Flutter suite passed 890 tests with 4 opt-in checks skipped. The targeted tests cover restart draft restoration, ownership isolation, missing files, accepted/uncertain sends, duplicate taps, typing during acknowledgement, cached reopen, technical routes, session YOLO and approval request replacement/failure. Personal 2.1.3 / ARM64 code 21462 is the build for this delivery; build/install results are recorded in the delivery sequence.

The owner-facing roadmap remains the scope authority. No transcript database, task outbox, compatibility layer, new command-discovery button or background-push implementation was added.

## Cold-start draft access in 2.31.7

Saved drafts are discoverable from the ordinary Chats screen even when Hermes no longer lists the original unsent chat. This reads the existing draft records for the exact connection/profile and reuses verified session resume or explicit draft recovery. It adds no local conversation records. Ambiguous resume errors preserve the source, duplicate taps cannot create duplicate replacements, and uncertain work is never sent automatically. The original Samsung failure and a second process-removal cycle passed; current evidence is in the [QA sweep](QA_SWEEP_2026-09-13.md).
