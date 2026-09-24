# Remaining notification test capabilities

Read-only source investigation, **24 September 2026**. Current public upstream
Hermes main verified at **`65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5`**. This is
source capability evidence, not proof of the deployed version, enabled toolset,
or a successful phone test. No backend operation, policy change, credential
change, production edit, build, or live request was performed by this study.

The [canonical test ledger](2026-09-20-notification-test-status.md) remains the
authority for device outcomes: 7 passed, 2 partial, 10 blocked in its original
19-scenario suite, with both subsequent focused bug retests passed.

## Approvals: no per-command “ask” parameter

The stock model-facing `terminal` schema exposes command, background, timeout,
workdir, pty, notify, and heartbeat. It has **no require-approval/ask flag**.
An internal `force` argument is explicitly outside the schema and bypasses a
guard; it is not a way to request an approval. Do not call internal Python
helpers or fabricate gateway requests to turn this into an integration test.
[Terminal schema and internal argument](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/tools/terminal_tool.py#L1248).

Desktop's Manual / Smart / Off control is **profile-scoped persisted
`approvals.mode`**, not a per-chat ask mode. The store keys state by profile and
uses `config.set`; the backend writes the configuration and refreshes session
information. A fresh chat does not isolate this change.
[Desktop store](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/apps/desktop/src/store/approval-mode.ts#L49),
[backend configuration write](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/tui_gateway/methods_config_set.py#L337).

Smart mode can approve a flagged but harmless operation before asking a human.
Consequently, repeating the previous safe probe cannot guarantee a request;
making it riskier merely to defeat Smart is inappropriate for this test.
**A concrete separately authorized option** would be temporarily selecting
Manual for an isolated test profile, using a verified disposable-file operation,
then restoring the exact prior mode. Manual skips the Smart decision stage; it
does not mean every harmless shell command is flagged, and existing pattern
allowlists may still apply. This study does not authorize or perform that change.
[Gate behavior](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/tools/approval.py#L794).

**Prefer print-only `execute_code` for single approvals once that policy change
is authorized.** An exact tool payload such as
`{"code":"print('WING-N06-ONCE')"}` reaches the whole-script approval guard
before execution. Unlike terminal detection, this guard can ask about a
completely harmless script: in gateway/ask mode it applies to all scripts,
with Manual omitting the Smart pre-decision. Preconditions remain important:
no existing `execute_code` session/permanent grant, no YOLO/off mode, and no
isolated backend that intentionally skips this guard. It is not guaranteed
merely by requesting it in chat. Once and Deny can be tested without file
changes. For a longer preview, use harmless comments plus one print statement,
keeping the exact script reviewable.
[Execution guard call](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/tools/code_execution_tool.py#L729),
[whole-script guard](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/tools/approval.py#L1234).

The scope warning is concrete: that script's pattern key is **`execute_code`**,
so Session/Always allowlists script execution generally for the relevant scope,
not just the literal print expression. **Do not click Always for a print-only
probe under the assumption that its permanent grant is narrow.** A session grant
also prevents later same-session print-only requests from prompting; run any
separately authorized session-scope test last in a disposable chat.
[Pattern key and allowlist lookup](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/tools/approval.py#L1248).

FIFO requests are supported through real desktop terminal batching: adjacent
terminal calls can prepare approval requests before execution when the session
source is `desktop` and its approval callback is present. Mixed nonterminal
barriers are not included. Therefore “terminal tools are sequential, so queued
approvals are impossible” is incorrect; generation still depends on real policy
gates and the model issuing a qualifying batch. Session/Always testing additionally
changes consent scope; permanent pattern grants remain separately authorized.
[Desktop terminal approval batch](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/agent/terminal_approval_batch.py#L251).

For a genuine harmless FIFO probe, create a fresh test-owned empty temporary
parent directory, confirm two distinct child paths do not exist, and issue two
separate terminal calls in one model batch, each exactly
`rm -rf -- /absolute/fresh-test-parent/absent-a` (then `absent-b`). Use literal
verified paths, no variables, globs, or existing user files. The recursive-delete
pattern is explicitly flagged by the current detector; Manual bypasses Smart
but existing pattern grants, isolated containers, or another policy can still
avoid the prompt. This is a flagged no-op on absent paths, not a dangerous
operation disguised as a test. Prefer the print-only route for every scenario
that does not need simultaneous requests. The earlier real-backend test already
used the analogous absent-path strategy successfully; do not count that as a
new physical-phone notification pass.
[Current detector](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/tools/approval_detection.py#L210),
[previous live evidence](2026-09-20-command-approvals.md#live-backend-follow-up),
[opt-in reproduction](../../integration_test/approval_queue_live_test.dart).

## Questions and continued work

`clarify` accepts **one to five questions in one request**, which is already
covered by the successful three-question run. The gateway waits for that single
request and supports per-question locking. It does not create five independent
pending request IDs.
[Tool schema](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/tools/clarify_tool.py#L244),
[gateway bridge](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/tui_gateway/server.py#L1339).

`clarify` is explicitly a **never-parallel barrier** in the stock tool scheduler;
later calls cannot cross it. Asking one ordinary agent turn to issue two clarify
calls concurrently, or to start another ordinary tool after the first unresolved
clarify, does not establish those scenarios. Multiple open request support in
the gateway is not proof that this tool route can generate them.
[Admission and ordered barriers](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/agent/tool_dispatch_helpers.py#L27),
[segment planner](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/agent/tool_dispatch_helpers.py#L164).

Useful safe test designs, subject to actual runtime evidence:

- **New request after dismissal:** dismiss question A, answer A on desktop, then
  let Hermes ask question B. B should create a fresh alert. This tests a new
  request after resolution; do not record it as simultaneous pending requests.
- **Watcher active during desktop resolution:** keep a separate chat doing a
  bounded harmless `sleep`, observe that monitoring is already running, then
  answer the first chat's question on desktop while Wing stays backgrounded.
  This can exercise global ongoing monitoring and multi-chat isolation; retain
  traces proving the relevant watcher was active and actually reconciled the
  resolved chat. A foreground reconnect alone is not that branch.
- A terminal launched **before** clarify with `background: true` can continue
  running while the question waits. That is a real existing process, not a
  second agent tool started across the clarify barrier. `notify: true` requests
  completion delivery, but source support alone does not establish Wing's
  monitoring classification for that state.
  [Stock background/notify schema](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/tools/terminal_tool.py#L1376).

These are proposed procedures, not executed outcomes. Do not relabel the
simultaneous-new-request or same-chat mixed-priority branches as passed using a
different-chat or sequential substitute.

## Secure input: a conditional dummy-code route exists

There is no generic exposed “show a secret prompt for testing” tool in the
inspected entry points. Stock secure requests belong to real flows: sudo,
named environment secrets, vault unlocking, saving a site login, or entering a
one-time code. The environment-secret callback **persists** a nonempty answer;
vault save likewise stores credentials. Dummy input in those flows is not
side-effect-free and should not be used here.
[Secure request contracts](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/tui_gateway/contracts/server_requests.py#L98),
[callback persistence](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/tui_gateway/agent_callbacks.py#L193).

**A genuine stock route worth checking is `browser_vault_enter_code`**, if it is
exposed by the deployed runtime and its managed browser is available. With no
saved-login handle, it asks through the official `vault.code` callback when the
current browser page has a recognized OTP input. It fills the answer directly
into that origin-bound page, reports counts rather than the value, and does not
save a vault entry or environment secret. Without an actual recognized field,
it returns `no_code_field` before prompting.
[Implementation](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/tools/browser_vault_tool.py#L331),
[exposed schema](https://github.com/NousResearch/hermes-agent/blob/65d01a7c22d3c62576bfe5f0fd875cbc9ab42be5/tools/browser_vault_tool.py#L664).

A safe conditional procedure is a disposable **trusted local HTTP test page**
with a labeled `<input autocomplete="one-time-code" name="otp">`, no JavaScript,
form submission, external resources, account, or real authentication. Open it
through the managed browser, invoke the stock tool without a handle, background
Wing, verify the generic private alert, and enter only a fixed dummy code such
as `123456` (or cancel to test cleanup). Do not submit the page. Shut down the
disposable page server and remove its files afterward. This requires ordinary
test-fixture setup and browser access, not a custom Hermes endpoint or backend
patch. Whether local navigation is allowed and the tool is actually exposed
must be checked before attempting it; this study has not done so.

This route differs materially from real account login or vault modification.
If those runtime prerequisites are unavailable, keep scenario 17 blocked;
native synthetic rendering may provide narrower UI evidence but cannot count as
a real secure-input integration pass.
