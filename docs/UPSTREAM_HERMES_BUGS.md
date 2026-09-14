# Upstream Hermes bugs

Tracks backend failures and contract gaps reproduced during Android acceptance. This records backend evidence and links to local tracking issues. Upstream reports are listed separately. No backend source changes are authorized by these entries.

Last verified: 2026-09-14, local Hermes 0.21.2, installed source commit `e16f686706b1e0d5334fd1ae82190058d2a19694`, using the Android emulator and real model/browser execution. See [Testing](TESTING.md) for the recorded acceptance baseline.

| ID | Priority | Issue | Status | Upstream issue | Local issue |
| --- | --- | --- | --- | --- | --- |
| HUP-001 | High | Browser and vault target different tabs | Open, reproduced | Not filed | [#19](https://github.com/tarkilhk/hermes-android/issues/19) |
| HUP-002 | Medium | Non-default profile loop command/control mismatch | Open, reproduced | Not filed | [#20](https://github.com/tarkilhk/hermes-android/issues/20) |
| HUP-003 | Medium | Global activity omits child-only work | Open, reproduced contract gap | Not filed | [#21](https://github.com/tarkilhk/hermes-android/issues/21) |
| HUP-004 | Medium | Windows profile deletion fails with an open MCP log handle | Open, fix proposed | [Issue #110953](https://github.com/NousResearch/hermes-agent/issues/110953), [PR #110954](https://github.com/NousResearch/hermes-agent/pull/110954) | [#22](https://github.com/tarkilhk/hermes-android/issues/22) |

Priorities reflect mobile impact. Close an entry only after its acceptance criteria pass against a recorded backend version. Add the upstream issue URL and fix commit when available; a newer version alone does not establish a fix.

## HUP-001: Browser and vault target different tabs

**Mobile impact:** Android receives working save-login forms, but Hermes associates the saved login with the wrong site and cannot fill the intended page. Verification-code submit/cancel remains unverified.

**Reproduce:** In a disposable profile, serve the [dummy login/code page](../integration_test/fixtures/vault/index.html) on loopback port 51165. Have Hermes call `browser_exec` with `new_tab("http://127.0.0.1:51165/"); wait_for_load(); print(page_info())`, omitting the `session` argument. Then call `browser_vault_save_login`, cancel once, and request it again to submit dummy values. Check the saved record's origin and fill result. An earlier run also called `browser_vault_enter_code` without a handle.

**Expected:** Browser navigation, vault origin detection and secret filling address the same page. The saved origin is `http://127.0.0.1:51165`; the code field triggers Android's code form.

**Observed:** The browser call succeeds on the fixture. Save cancellation returns `save_declined`. Submission saves an item with origin `chrome://new-tab-page` and a fill error stating that no login fields were found. Code entry returns `no_code_field`. Omitting the named browser session reproduces the mismatch, so that argument does not explain it by itself. The internal tab-selection root cause is still unproven.

**Evidence:** Session `20260914_162154_249a06` confirms the default-session reproduction; `20260914_161737_e11b8f` contains the OTP failure. Local captures: `build/qa-vault-final-readback.json`, `build/qa-vault-final-20260914.log`. These captures are ignored, machine-local artifacts; the findings above and committed test/fixture remain available after a clean clone.

**Fix direction:** Investigate backend browser/vault target selection and supervisor binding. Do not assume an Android form change can select the correct backend tab.

**Retest to close:** Run the vault case in [the native driver](../integration_test/remaining_product_live_test.dart). Verify correct origin, successful password/code filling, save and code cancellation, no secret leakage into history/drafts, and removal of the dummy record. Check both default and named browser sessions if upstream claims support for both. Existing save/cancel success does not satisfy the remaining fill/code checks.

## HUP-002: Non-default profile loop command/control mismatch

**Mobile impact:** A loop starts in a non-default Hermes profile, but Android's structured controls cannot see or manage that same loop.

**Reproduce:** Create a disposable chat in `android-qa-a`. Use `command.dispatch` for `/loop 30s Reply exactly LOOP_SCOPE_CHECK --times 2`, then `/loop status`. Read that chat's structured session controls. Stop the owned loop through `/loop stop` afterward.

**Expected:** Start, status, pause, resume and stop refer to the same loop in the selected profile/session.

**Observed:** Command output reports `Loop set` and `Loop (active, every 30s, 0/2 runs, due now)`, while structured controls contain no loop. `/loop stop` succeeds and subsequent status reports `No loop set`. Source inspection points to different profile scoping in command and structured-control paths.

**Evidence:** The `nondefault loop command and controls address the same local work` case in [the native driver](../integration_test/remaining_product_live_test.dart); local capture `build/qa-remaining-native-20260914.log`. The recorded result is `backend_limited`, not successful control acceptance.

**Fix direction:** Align backend loop lookup and mutation scope across command and structured APIs.

**Retest to close:** Start a finite loop in a non-default profile; verify structured status sees it, pause/resume/stop work, and a second profile is unaffected. Read back the stopped state. Default-profile success alone does not close this entry.

## HUP-003: Global activity omits child-only work

**Mobile impact:** Activity can miss ongoing work when a parent chat is idle but a delegated child is still running, unless that client has already opened the parent and loaded its child roster.

**Reproduce:** Start one real background child from a disposable parent chat and allow the parent to become idle while the child continues. Compare the loaded parent's child roster with `session.active_list` and Activity in an independent client that has never opened that parent.

**Expected:** Global activity provides enough server-owned information to discover that the parent still has active child work across profiles.

**Observed:** The open chat sees one active child. The global parent row is idle with no child count, and the independent client's Activity omits it. After child completion and the parent's final rollup, the loaded Activity state clears correctly.

**Evidence:** The `unopened parent with actual child work is compared with global status` case in [the native driver](../integration_test/remaining_product_live_test.dart); local capture `build/qa-remaining-native-retest-20260914.log`. Recorded fields: `parent_status: idle`, `server_child_count: null`, `active_children_in_open_chat: 1`, `unopened_parent_visible: false`.

**Fix direction:** Expose child-only ongoing work through the global backend activity contract. Avoid a client workaround that opens every historical chat to discover its children. This is a missing contract capability; upstream intent has not been established.

**Retest to close:** With an independent client that has never opened the parent, verify the ongoing parent/child appears across profiles, opens the correct chat, and disappears after all work and final rollup finish. Include reconnect while only the child is active.

## HUP-004: Windows profile deletion fails after MCP activity

**Upstream contribution, 2026-09-14:** Filed [issue #110953](https://github.com/NousResearch/hermes-agent/issues/110953)
and [PR #110954](https://github.com/NousResearch/hermes-agent/pull/110954).
The reproduction also fails on upstream main `62e5f466565ee56351e4483ead8e62f9e782f8b3`.
Proposed fix `1f21bcc6c51fd03943dd19cfa6ac401374fcfa8e` stops this process's
profile-scoped MCP resources and releases their cached stderr handles before
deletion. Both regression tests were proven red on base and green with the fix.
The actual HTTP handlers also passed with a real MCP subprocess and disposable
profile. Broader validation: 202 passed, 36 skipped, and five failures reproduced
unchanged on base. Ruff and the Windows footgun check passed.

At the recorded check, the PR was open and the installed backend was unchanged. Follow the linked PR for its current status. Related
[issue #87761](https://github.com/NousResearch/hermes-agent/issues/87761) and
[PR #87787](https://github.com/NousResearch/hermes-agent/pull/87787) address a
running gateway service, which this reproduction does not require.

**Mobile impact:** Deleting a profile can return HTTP 500 after a connector has
started because the backend still owns an open log handle.

**Reproduce:** In an isolated Hermes home on Windows, create a profile, configure
a stdio MCP service, and enable/test it. Delete that profile through
`DELETE /api/profiles/<name>` while the backend remains running.

**Observed:** Hermes reports `[WinError 32]` for the profile's
`logs/mcp-stderr.log`, and the deletion request fails. Stopping the owned QA
backend process tree releases the handle and permits filesystem cleanup. The
same emulator lifecycle test deletes profiles without MCP handles successfully.

**Evidence:** [Administration acceptance](TESTING.md#recorded-live-baseline),
local `build/admin-live-run2.log` and `build/admin-live-run2-backend.err.log`,
backend revision `e16f686706b1e0d5334fd1ae82190058d2a19694`.

**Retest to close:** Start/test a stdio connector in a disposable Windows profile,
delete it while Hermes remains running, and verify successful deletion and
released processes/file handles without affecting another profile.

## Related items that are not filed as bugs

- Shared older answer versions require server persistence that is absent from the current contract. Ordinary regeneration, durable replacement and separate forks passed. Track shared alternatives as a capability request if selected, not as HUP-001 through HUP-003.
- External vault unlock requires a configured external password manager. The local environment has none; this is an untested prerequisite, not a reproduced defect.

Local tracking issues are indexed in [Bug tracker](BUG_TRACKER.md). The evidence above is dated; do not close a backend entry solely because a newer version exists.
