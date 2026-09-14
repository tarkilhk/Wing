# Final five acceptance checks, 2026-09-14

This pass uses the actual local Hermes dashboard/gateway and configured model. Native interaction runs on the single existing Android emulator. Backend source is unchanged. Work is limited to disposable QA profiles, chats, an empty Git repository and dummy vault data.

Ongoing backend follow-up is tracked in [Upstream Hermes bugs](UPSTREAM_HERMES_BUGS.md), with stable IDs, reproduction evidence and closure criteria.

## Results

| Item | Result and evidence | Remaining boundary |
| --- | --- | --- |
| Regeneration and answer versions | Passed actual regeneration, durable replacement, separate fork and reopen through an independent Android controller. `test/answer_sync_acceptance_live_test.dart`, `build/qa-final-host-20260914.log`. Explicit stored server row IDs differ before/after regeneration. | Fresh server history contains one replacement, not superseded alternatives. Desktop's picker uses same-client state; shared versions have no current server persistence contract. |
| Child-only activity | Confirmed backend limitation with a real delegated child. Open chat knew about one active child; the global session row was idle with no child count. An independent client that had not opened the parent omitted it. After child completion and parent rollup, Activity cleared. | Current global response cannot identify unseen child-only work. No Android fix or backend change claimed. |
| Non-default profile loops | Confirmed backend limitation. In a QA profile, `/loop` started real work and `/loop status` reported it, while structured session controls reported no loop. `/loop stop` succeeded and status confirmed none remained. | The command and structured-control paths resolve different loop scopes. Default-profile coverage does not prove this behavior. |
| Vault forms | Partially passed. Actual save-login cancel and submit forms worked, and the dummy record was removed. Full acceptance failed: the browser loaded the fixture but the vault saved against `chrome://new-tab-page`; fill failed, and the earlier OTP attempt returned `no_code_field`. A retry without a named browser session reproduced the wrong origin. | OTP submit/cancel and successful page fill remain blocked by the reproduced backend browser/vault targeting mismatch. External-manager unlock is also unavailable because no external manager is configured. |
| Session and Always approvals | Passed actual Session and Always buttons, repeat execution, persisted rule, fresh-chat reuse and isolation to the other profile. Deny there saved exit code -1 with blocked status; approved commands saved exit code zero. | No remaining acceptance gap for these options. Modes, allowlists and fixture skill state were restored and checked. |

Child evidence: `build/qa-remaining-native-retest-20260914.log`. Loop evidence: `build/qa-remaining-native-20260914.log`. The driver reports `backend_limited` separately from `passed`; a green limitation assertion is not feature acceptance.

Approval evidence: `build/qa-remaining-acceptance-20260914.log` and independent saved-history readback in `build/qa-approval-final-readback.json`. Final sessions: Session `20260914_161834_3604de`, Always `20260914_161851_6c68dc`, fresh chat `20260914_161906_3492a6`, other-profile Deny `20260914_161919_4a0d21`.

Vault evidence: `build/qa-vault-final-20260914.log` and `build/qa-vault-final-readback.json`, session `20260914_162154_249a06`. Its saved `browser_exec` arguments omit `session` and load the correct fixture URL; the saved vault result still reports the wrong origin. Earlier OTP evidence is in session `20260914_161737_e11b8f`. The root cause inside backend tab selection remains unproven. No Android browser-target parameter or backend source change was invented to bypass it.

The final host pair passed with strict success/status and durable-row assertions. Focused static analysis passed for all three new Dart drivers. Native approval passed; native vault intentionally remains a failing acceptance case. The later added Deny-result and loop-output assertions were checked against captured real responses, not rerun as another native batch. The full suite was not repeated for test/documentation-only changes. No release version or feature changelog entry is needed.

## Failed attempts and corrections

- The first approval fixture belonged to the sandbox Windows identity. Git refused it with exit code 128. A separate empty repository created under the backend user's identity corrected the fixture. No global Git trust setting changed. Actual exit code zero is now required.
- A model clarification interrupted one approval attempt. The driver now handles one explicit clarification and requires a real terminal result.
- An old disposable `android-mobile-slash-qa` skill instructed Hermes to return a fixed marker without tools. Saved transcripts confirmed the model loaded it instead of running the requested terminal action. The final driver temporarily disables this fixture in the two QA profiles and restores its enabled state afterward.
- The first child cleanup assertion ran before the parent's final rollup finished. The corrected test waits for that real completion; the retest passed.
- A temporary compile error in concurrent chat-moving work prevented one build. Its owning task corrected it before the next build. No QA result is attributed to the failed build.
- An instrumented vault attempt failed during the pre-submit `/api/profiles` read with a closed HTTP connection. No prompt or tool ran and no login was saved. The driver permits one retry only for this confirmed pre-submit failure, with the draft retained and delivery not uncertain.
- With the interfering skill disabled, actual Session and Always execution, reuse in a fresh chat and the other profile's approval request all succeeded. The last Deny click failed because the test selected `TextButton` instead of the actual `OutlinedButton`. The finder was corrected before retesting.
- One rebuild hit a stale Gradle lease. Process inspection showed only the idle daemon; normal `gradlew --stop` released it. This tooling failure produced no acceptance result.
- The real save-login forms worked, but the model opened the fixture in a named browser session while the vault tool inspected a different tab. The stored dummy origin was `chrome://new-tab-page`, and code entry returned `no_code_field`. Cleanup removed that dummy login. The corrected prompt omits the session argument, and the driver asserts the saved origin. The retry reproduced the mismatch, so named-session selection was not a sufficient explanation.
- A custom WebSocket browser preflight was inconclusive because it did not capture submit acknowledgement or the full event envelope. A later production-controller probe superseded it and confirmed real browser success. See `REMAINING_CONTRACT_CHECKS_2026-09-14.md`.

## Cleanup and repeatability

The native driver restores approval mode and allowlists, restores the QA skill state, stops its own unfinished work, and removes only its unique-label dummy vault item. It checks each restoration. The owned Git fixture contains one empty commit and no user files. The loopback form server serves only a dummy login/code page. Completed QA chat records remain as evidence; stopping work does not mean deleting its history.

Host tests are opt-in via `HERMES_TEST_PORT`. The native driver also requires `QA_APPROVAL_REPO` pointing into `build/qa-approval-scope-*`, an existing empty repository owned by the backend user. Forward the chosen backend port to the emulator with ADB reverse. Serve the committed dummy page with `python -m http.server 51165 --bind 127.0.0.1 --directory integration_test/fixtures/vault`. No user password, vault record or external service is needed.

Do not rerun completed scenarios solely to obtain an all-green headline. Recheck a confirmed backend limitation only after its relevant contract changes.

The dummy HTTP server was stopped after the pass. The single emulator was released to the other task; no additional emulator or phone session was started.

Independent final readback confirms both QA profiles returned to Smart approval mode with empty allowlists and the fixture skill enabled. The saved vault test history contains no dummy password. Evidence: `build/qa-final-cleanup-readback.json`. The full OTP and draft-leak assertions were not reached and remain unverified.
