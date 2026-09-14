# Conversations and saved-answer actions

## Drafts and sending

Draft text and staged files persist per connection identity, canonical profile and durable chat. Navigation and restart preserve unsent work. Missing local files must not erase the text. An accepted send clears only its submitted snapshot; newer typing and attachments stay in the composer.

Restore server history and status before continuing work. Do not automatically resend after an uncertain acknowledgement. Normal sends still have a process-death window where a retained draft can return without an uncertainty warning; check history before resending. See [issue #17](https://github.com/tarkilhk/hermes-android/issues/17).

Saved drafts remain discoverable when their chat is absent from a loaded server page. Recover to a new chat only after a confirmed missing-session result, not an ambiguous request failure. Move the draft in one durable storage operation, reset old upload receipts, pause queues and require explicit Send.

The idle action is Send. Busy actions and accessible alternatives follow [Composer actions](COMPOSER_ACTION_GESTURE.md). [Queues](SUPERVISION_AND_QUEUES.md) remain separate from the current draft.

## Edit, regenerate and fork

Edit targets a saved user row by durable identity, verifies fresh history and confirms replacing that turn and later history. It preserves unrelated composer work and pauses queued follow-ups. Internal deliveries must not become editable human prompts.

Regenerate replaces the answer in the same chat. Branch/Fork creates a separate chat with an explicit boundary. Ordinary regenerated replacement and fork reopen work through existing APIs; synchronized older alternatives require a server relationship/persistence contract. Do not call invented answer-version methods or recreate a phone-only version database. See [Server chat relationships](SERVER_CHAT_RELATIONSHIPS.md).

After compaction, branch validation compares source and child saved REST history using `include_compacted=true`, raw roles/text and expected row counts. The shorter RPC display history is not an adequate copy boundary. If copied history is missing, changed or extra, retain the created child and report the failed validation explicitly rather than hiding the partial outcome.

## Attachments in history

Images use `image.attach_bytes` with filename, base64 content and session receipt. Generic files use `file.attach`; its returned `ref_text` precedes the visible question in the normal prompt. Reuse this contract for queue submission.

Saved user display removes generated expanded attachment context while preserving raw history and row identities. Restore missing references once, without expanding them again; assistant content is not subject to user-context stripping. An upload receipt proves staging, not that a model read the file. Automatic `@file` expansion can reject a staged path outside the workspace, matching the observed Desktop contract. Do not paste file bytes or rewrite the reference to conceal that backend boundary.

## Model, context and reading

Choose models by the server's technical provider route and supported reasoning options. `/yolo` uses the current session's configuration and displays its returned state; it must not change global defaults.

The thin context ring beside the model selector uses server usage or a labelled estimate. Unknown is not zero. Warning thresholds are 65% and 85%. After cold resume, the lazy agent's ready event triggers a guarded `session.info`/breakdown refresh, without submitting a prompt or polling indefinitely.

Markdown, code and tables retain copying and horizontal overflow where appropriate. Long content supports bounded reading and return to latest. Find and tool progress are covered in [Execution and search](EXECUTION_FIND_AND_OUTPUTS.md); [output viewers](OPENING_OUTPUT_FILES.md) handle files. [Transcript projection](TRANSCRIPT_DISPLAY_TYPES.md) defines compact internal notices while preserving raw server history.
