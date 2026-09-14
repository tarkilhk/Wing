# Remaining contract checks, 2026-09-14

Scope: inspection of the installed Hermes agent at commit `e16f686706b1e0d5334fd1ae82190058d2a19694`, followed by disposable local runtime probes. The source review was read-only. The later probes created QA sessions and invoked the real model and browser. No backend source was changed. Final acceptance results are recorded separately in `QA_FINAL_FIVE_2026-09-14.md`.

## Regenerated answer versions

The current Desktop renderer supports answer versions created by Regenerate while its local client state retains the old answer. `planReload` assigns the old answer and replacement answer the same `branchGroupId`, hides the old assistant answer during the new turn, and carries the group into the streamed replacement. `runtime-repository.ts` maps assistants with the same group to the same parent. The assistant footer renders `BranchPickerPrimitive` previous/next controls and a count, hidden when there is only one branch.

Evidence:

- `apps/desktop/src/app/session/hooks/use-prompt-actions/rewind.ts:473-524` builds the regenerate plan, reuses or creates the group, and preserves the old answer as a hidden version.
- `apps/desktop/src/app/session/hooks/use-message-stream/index.ts:113-123, 636-648` assigns the pending group to streamed and final replacement answers.
- `apps/desktop/src/app/chat/runtime-repository.ts:52-57` gives grouped assistants the same assistant-ui parent.
- `apps/desktop/src/components/assistant-ui/thread/assistant-message.tsx:688-692, 779-795` exposes Regenerate and the same-client version picker.
- `apps/desktop/src/lib/inflight-turn-journal.ts:352-364` preserves `branchGroupId` and `hidden` in the in-flight recovery journal.
- `apps/desktop/src/types/hermes.ts:664-705` defines the backend `SessionMessage` contract. It has no `branchGroupId` or answer-version field.
- `tui_gateway/session_history.py:181-244` projects stored history to the resume wire format. It emits role, text, timestamp, row identity, assistant detail, and display metadata, but no branch group or superseded answer.
- `tui_gateway/methods_prompt.py:241-267, 513-530` treats Regenerate as confirmed durable truncation before the replacement submit. The backend history contract does not retain the removed answer as a sibling version.

Contract conclusion: Desktop has same-client Regenerate-to-version-picker behavior. It is not a server-synchronized shared-version contract. `branchGroupId` exists only in Desktop client state and its in-flight journal; fresh history hydration cannot reconstruct the removed answer or the group. I found no separate backend "answer versions" API. Android can match the current same-client behavior locally, but cross-client or post-restart shared versions would require a new persistence contract. Source inspection does not prove the live same-client interaction, which remains an actual Desktop UI test.

## Vault and browser prerequisites

The running dashboard answered `GET /api/status` with HTTP 200, version `0.21.2`, dashboard self-test `ok`, storage `ok`, and no active gateway. That route contains no browser or vault readiness fields. `hermes_cli/web_routers/tools.py` has toolset, terminal, and computer-use reads, but no browser or vault status route. The protected toolset route returned HTTP 401 without dashboard authentication.

The runtime's read-only schema checks reported:

- Browser Use CLI mode: selected and discoverable.
- Built-in browser mode: false by design while Browser Use CLI replaces it.
- Vault tool schema gate: available.
- Enabled vault backend: local only; no locked external manager.
- Local vault metadata listing: indeterminate from this QA process. Windows denied this sandbox identity access to the Hermes vault directory, so the reported zero items is not evidence that the user's vault is empty.

Relevant contracts:

- `tools/browser_vault_tool.py:41-52` advertises vault tools when Browser Use CLI mode or the built-in browser requirements are ready.
- `tools/browser_use_cli.py:206-214` defines Browser Use CLI mode and its configured/default resolution.
- `tools/browser_tool_install.py:294-329` explains why the built-in readiness result is false in Browser Use CLI mode.
- `tools/browser_vault_tool.py:212-250` is the metadata-only listing contract. It returns handles and metadata, never passwords.
- `tools/browser_vault_tool.py:78-136` requires a supervised CDP WebSocket for secret-bearing fills and refuses the argv fallback.
- `evals/vault_fill_live_e2e.py` documents the real-browser test path. It creates an isolated temporary vault, starts Hermes Chromium, and exercises fill behavior, so it is not a read-only preflight and was not run.

Schema advertisement alone did not establish browser operability. The earlier 120-second timeout was superseded by a successful real `browser_exec` call through Android's production controller. `test/browser_prerequisite_live_test.dart` opened `about:blank` and returned page information with `success: true` and `exit_code: 0`. Session `20260914_155042_4205c2` completed normally. Evidence is in `build/qa-remaining-host-20260914.log`. This establishes the browser prerequisite, not acceptance of vault forms.

An existing-user-vault check is unnecessary for implementation QA and should not be used from this sandbox. `evals/vault_fill_live_e2e.py` is a bounded real-browser test with an isolated temporary `HERMES_HOME`. It starts a loopback login and checkout server, creates dummy login and payment records, opens pages through the real `browser_exec` path, verifies supervised fill and redaction, checks that a declined payment writes nothing, then removes or discards the temporary data. It also installs in-process fake prompt callbacks to exercise save-login and payment confirmation. It does not exercise a real user's unlock UI, external password manager, OTP prompt, or `browser_vault_enter_code`. It launches Hermes Chromium and writes only temporary fixture data, so it is suitable only when those actions are explicitly allowed and browser runtime operability has been restored.

### Actual harmless runtime probe

One disposable probe was submitted through the real gateway WebSocket at `ws://127.0.0.1:51163/api/ws` under profile `android-qa-b`. `session.create` returned without an RPC error and supplied runtime session ID `c605b863`. The harness did not retain the other create-result fields or a durable stored-session ID. The subsequent `prompt.submit` request contained exactly `session_id`, `profile`, and `text`. Its text required one `browser_exec` call that opened `about:blank` and printed `page_info()`, with no other URL or vault use.

The harness did not retain a successful `prompt.submit` acknowledgment or its status. It would have stopped and recorded an RPC error if it received an error response with the submit request ID, but no such error was recorded. It filtered inbound events for possible tool and terminal names rather than retaining an event-type count, so the available record cannot show whether gateway or model progress events arrived under a different envelope. No browser tool-call, browser tool-result, assistant terminal result, or browser error matched the filter before the 45-second deadline. The client then sent `session.interrupt`; the gateway acknowledged it without an RPC error. The disposable title was absent from a later profile session listing, and no durable ID was available for a transcript lookup.

Actual outcome: inconclusive preflight. The record proves gateway session creation and interrupt handling, but it does not prove that `prompt.submit` reached a model or that `browser_exec` started. It provides no evidence about Chromium health and must not be combined with the separate earlier browser timeout as confirmation. The subsequent production-controller probe retained the durable session ID and terminal tool result and passed, as recorded above. No real vault item or credential was read or used.


### Native vault follow-up

Real Android save-login cancel and submit requests were exercised successfully. The saved dummy record had the wrong origin, `chrome://new-tab-page`, although `browser_exec` had opened the local login/code fixture. The OTP tool consequently returned `no_code_field`. Retesting with the browser `session` argument omitted reproduced the wrong origin. The native acceptance remains failed at the origin assertion; it is not classified as an Android form defect. Cleanup removed the unique-label dummy item and restored the QA skill toggle. See `QA_FINAL_FIVE_2026-09-14.md` for session IDs and evidence.
