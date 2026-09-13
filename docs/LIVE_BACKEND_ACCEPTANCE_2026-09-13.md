# Live backend acceptance

This continuation tests the Android emulator against the existing local Hermes
server. Gateway replies and model/tool events are real. Simulated server tests
do not count as live acceptance.

The requested checks authorize disposable application data: synthetic chats,
one nonce-named project that is deleted afterward, and temporary profile
description/SOUL values that are restored and independently read back. They do
not authorize backend code, configuration, deployment or database repair.

## Reproduce the live suite

Prerequisites are a running stock Hermes server, an Android emulator with ADB
and Flutter available, the `default` profile with `gif-search` installed and
`TENOR_API_KEY` absent, and `android-qa-a` with a working provider and repository
root. Choose the server's local port and expose it to the emulator:

```text
adb reverse tcp:<port> tcp:<port>
flutter test integration_test/backend_acceptance_live_test.dart -d <emulator> --dart-define=HERMES_TEST_PORT=<port>
```

The suite runs seven real-backend scenarios. The secret-expiry case waits for
the stock five-minute timeout; it uses no fixture or server timeout change.
Profile values are restored and the nonce-owned project is deleted during
cleanup.

| Check | Current result | Evidence |
| --- | --- | --- |
| Live todos | Passed. Hermes returned one in-progress and one pending task, then two completed tasks after Android answered a real clarification. Android displayed Tasks 0/2 and Tasks 2/2 with the correct item names. | `build/qa-live-todos-expanded.xml`, `build/qa-live-todos-final-expanded.xml`; owned session `20260913_221840_a97782` |
| Profile description/SOUL | Passed through the real editor. A separate gateway read the exact saved values, and cleanup restored and verified both originals. | Profile test in `build/qa-live-admin-driver.log.app.log` |
| Project lifecycle | Passed. Android created a nonce-owned project, renamed it, changed appearance, independently read the exact persisted values, deleted it, and verified exact owned cleanup. | `build/qa-live-six-retest-driver.log.app.log`; `integration_test/profile_admin_live_test.dart` |
| Goal Unwait | Passed. The test obtained an actual PID from an owned terminal result, set that real wait barrier, used **Resume now**, verified that the barrier cleared, and cleaned up the goal and process. | `build/qa-live-six-driver.log.app.log`; `integration_test/profile_goal_unwait_live_test.dart` |
| Secret cancellation | **QA-034 fixed and passed live.** Hermes emitted a real `TENOR_API_KEY` request from default `/gif-search`. Corrected **Cancel** completed at 15:17:56 UTC, and the untouched stock 300 s expiry completed at 15:23:25 UTC. | `build/qa034-focused-final.log`; `build/qa034-live-seven-driver.log`; `build/qa034-live-seven-driver.log.app.log`; `integration_test/profile_sensitive_live_test.dart` |
| Sudo cancellation | Passed against a real request. Android cancelled with an empty response and Hermes persisted the corresponding tool result. | `build/qa-live-six-driver.log.app.log`; `integration_test/profile_sensitive_live_test.dart` |
| Approval handling | The safe `-WhatIf` request auto-resolved on Hermes. Android received the real terminal event and the result was saved. This did not produce or test a manual approval card. | `build/qa-live-six-driver.log.app.log`; `integration_test/profile_sensitive_live_test.dart` |
| Vault | No password-manager backend is configured. No vault setup or credential change is authorized for this check. | Installed backend configuration metadata audit |

The first project/profile test build had an invalid `testWidgets` skip argument.
The first goal test build expected a boolean from the void `send` method. Both
were test-code errors caught before execution, not Android product defects.

All seven actual-backend scenarios passed in 7 minutes 7 seconds with driver exit
0. The runner reported `+8` because it counted teardown after seven
`testWidgets` scenarios. QA-035's focused collapse and alignment checks pass.
Its filtered real-sudo emulator test also passed with exit 0: Activity started
collapsed, expanded only after a tap, kept sensitive Cancel visible outside,
and allowed the real tool turn to complete. Evidence is
`build/qa035-activity-live.log`.

An earlier dated review withheld project and profile writes. The user's later
explicit authorization supersedes that limit for these disposable application
writes and their cleanup. Backend code, configuration and deployment remain out
of scope.
