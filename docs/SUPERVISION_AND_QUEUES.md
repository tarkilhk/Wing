# Queues, Activity and pending input

## Follow-up queue

Queue moves the current text and staged files into an unsent entry owned by the original connection/profile/chat. Attachment-only entries are supported. Steer is text-only. The current draft stays separate, and Queue waits for an in-flight submission to finish before taking its text or files.

Entries appear above the composer in a bounded scroll area. Hold a row to edit it in the composer. Queue saves the edit at the same position; Steer sends it into the current turn and removes it only after acknowledgement. Cancel, successful save, accepted steering or confirmed deletion restores the separate draft. Delete targets entry identity and requires confirmation. Back first hides the keyboard, then cancels editing. The queue cannot drain while an edit is open.

Drain one entry at a time after a completed turn, while the app is connected. Refresh server state before draining restored work. Persist upload receipts and a paused marker before submission. Stop, upload/send failure or uncertainty pauses the remaining entries for explicit review/resume. A restart must not automatically repeat uncertain work.

Staged files belong to the composer or one queue entry. Queueing transfers their references without copying the files. Clean up only after successful durable removal following acknowledged send or explicit Remove. Failed local writes preserve queued work and newer composer edits. Pending steering remains durably paused until its acknowledgement.

## Activity ownership

Activity discovers running and input-required work across profiles on the selected connection. A global runtime snapshot does not establish profile ownership. Join durable IDs against profile-scoped metadata or a previously verified exact runtime/durable pair. Unknown or ambiguous owners stay unavailable; report failed-profile coverage instead of presenting stale rows as current.

Enumeration must not resume every saved chat. Resume can attach or adopt a runtime and is appropriate only when opening verified work. Selecting an Activity row retains its original connection/profile/chat. Missing titles use a short session ID.

Child-only work can be absent when a parent is idle and the server supplies no child count. The open parent's roster may still see it. This limitation is tracked in [upstream bug HUP-003](UPSTREAM_HERMES_BUGS.md#hup-003-global-activity-omits-child-only-work). [Subagent supervision](SUBAGENT_SUPERVISION.md) describes loaded child controls.

## Sensitive input and approvals

Sudo, environment-secret, vault unlock, save-login and verification-code requests use dedicated forms. Current Hermes sends `sudo`, `secret`, `vault.unlock_prompt`, `vault.save_login` and `vault.code` server requests. The app matches the runtime session and frame ID, then answers with `request.answer` and `result.value`. For save-login, the value contains the identifier/password JSON expected by the vault callback. Match request identity, guard duplicate responses and clear only the request confirmed answered or expired. Values remain in memory, outside drafts, logs and conversation messages. Never retry a secret response under a different owner.

Resume restores outstanding form metadata from `open_requests` for the exact runtime. Typed credentials are never recovered or persisted. A matching `request.cancel` removes the form; a timeout is shown as expiry, not as a user choosing to decline. This replaces the former per-kind request/respond/expire protocol and `pending_sensitive` snapshot. Partial `session.info` events leave pending input unchanged unless they include `open_requests`. The upstream [secure callback wiring](https://github.com/NousResearch/hermes-agent/blob/main/tui_gateway/agent_callbacks.py) defines the request names and value formats. Vault page targeting has a separate reproduced backend bug; see [HUP-001](UPSTREAM_HERMES_BUGS.md#hup-001-browser-and-vault-target-different-tabs).

Supported approvals expose the server's request details and scopes, including Deny, Allow once, Session and Always. Display acknowledged outcomes and effective state. Clarification supports multiple questions; it remains distinct from sensitive credentials.

Clarification uses Hermes' server-initiated JSON-RPC `clarify` request. The app
routes it by `params.session_id` and retains the frame's string `id`. Batch
answers use `clarify.lock` with that ID and the supplied question ID; single
answers use `request.answer`. Resume restores forms and locked answers from
`open_requests`; `request.cancel` withdraws the matching form. This targets the
[current server-request protocol](https://github.com/NousResearch/hermes-agent/blob/main/tui_gateway/server_requests.py),
replacing the previous `clarify.request` / `clarify.respond` protocol.
Tool-call arguments or a timeout result in chat do not establish that the
request frame reached the app.

Reply params follow the [strict prompt contract](https://github.com/NousResearch/hermes-agent/blob/main/tui_gateway/contracts/prompt_voice.py):
`clarify.lock` accepts `request_id`, `question_id`, `answer` and optional `profile`;
`request.answer` accepts `id`, `result` and optional `profile`. Neither accepts
`session_id`. That field belongs to the incoming request; echoing it in a reply
causes RPC error 4000 before the answer reaches the handler. The test gateway
rejects unknown reply fields so form tests exercise this boundary.

## Side questions

`/btw`, `/bg` and `/background` retain the submitted question with their task kind and returned ID. An early completion must not be downgraded by a late acknowledgement. Show empty results explicitly and preserve existing cards on same-runtime reconnect when optional fields are absent.

Stock `bg.complete` does not contain the original question. There is no verified cold task snapshot, cancellation or durable linked-result recovery contract. Do not invent one or infer identity from matching text. Cards are transient client presentation, not a second server task ledger.

[Session controls](SESSION_CONTROLS.md) covers goals, loops and processes. [Notifications](BACKGROUND_NOTIFICATIONS.md) explains connected-app delivery and its limits.
