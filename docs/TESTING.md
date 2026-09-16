# Testing and acceptance

[Contributing](../CONTRIBUTING.md) covers the toolchain and ordinary analyze/test/build commands. [Windows build workflow](LOCAL_BUILD_SETUP.md) covers cache/lock handling and data-preserving installation. Complete the [release checklist](CODE_QUALITY_CHECKLIST.md) for a fixed release candidate.

## What a passing check establishes

Host unit/widget tests establish client behavior with their supplied responses. An emulator using injected gateways adds Android keyboard, layout and lifecycle evidence. A live-backend driver exercises the deployed contract. A signed phone run adds that device's permissions, native viewers and installation behavior. These results are complementary; none certifies every environment or a Play submission.

Keep logs and generated captures under ignored `build/`. Record source revision, backend revision, device, executed scenario and remaining limit in the PR or issue. Do not create another release-by-release documentation journal. Redact evidence using [Security](../SECURITY.md).

## Useful test entry points

| Boundary | Entry points |
| --- | --- |
| Ownership and administration | `test/administration_*_test.dart`, `test/profile_live_contract_test.dart`, `integration_test/administration_existing_server_live_test.dart` |
| Draft/queue acknowledgements | `test/profile_composer_queue_test.dart`, `test/profile_queue_submission_ownership_test.dart`, `integration_test/profile_lost_ack_live_test.dart` |
| Native queue editing | `integration_test/queued_message_edit_test.dart`, `integration_test/queued_message_native_preview.dart` |
| Saved history and branches | `test/answer_sync_acceptance_live_test.dart`, `test/profile_live_history_test.dart`, `integration_test/answer_branch_live_test.dart` |
| Sensitive input, goals and projects | `integration_test/backend_acceptance_live_test.dart` and its profile-specific companion drivers |
| Vault, approvals, loops and child-only work | `integration_test/remaining_product_live_test.dart` |
| Notifications | `test/chat_notification_test.dart`, `test/plugin_turn_notification_sink_test.dart`, `test/profile_notification_live_test.dart`, `test/profile_notification_coverage_test.dart`, `integration_test/profile_notification_test.dart`, `tools/qa/check_background_monitoring.py` |
| Launcher shortcuts | `test/android_launcher_shortcut_contract_test.dart`, `test/android_launch_intent_service_test.dart`, `test/home_config_restore_test.dart`, `tools/qa/check_launcher_shortcut.py` |
| Slash profile scope | `test/slash_profile_live_contract_test.dart`, `integration_test/slash_commands_live_test.dart` |
| Connection setup | `test/connection_address_test.dart`, `test/connection_setup_probe_test.dart`, `test/connection_setup_transport_test.dart`, `test/connection_setup_screen_test.dart` |
| Design renders | `test/studio_layout_test.dart`, `test/studio_controls_test.dart`, `test/studio_layout_regressions_test.dart`, `test/administration_navigation_test.dart` |

Read a driver's environment flags, mutations and cleanup before running it. Use disposable profiles/chats and owned fixtures on an authorized server. Live tests may invoke models, modify profile settings or start host tools. Restore changed values and independently verify cleanup; a green assertion that records `backend_limited` is not successful feature acceptance.

After installing an APK on an emulator, run `python3 tools/qa/check_launcher_shortcut.py --serial <emulator-id> --package com.tarkilhk.wing.dev` (use `com.tarkilhk.wing` for release or signed development builds). This read-only check verifies Android's registered Quick Chat, Activity and Search chats intents and resolves their activity. Gradle generates `xml/shortcuts.xml` from `android/app/src/main/shortcuts.xml.template` using each variant's application ID; intent targets must be literal package names because Android parses them with system resources. Flutter tests cover the subsequent cold/warm launch handoff, destination routing, search focus and draft preservation.

For a compatible local backend/emulator, the basic connection pattern is:

```text
adb -s <emulator-id> reverse tcp:<port> tcp:<port>
flutter test integration_test/backend_acceptance_live_test.dart -d <emulator-id> --no-uninstall --dart-define=HERMES_TEST_PORT=<port>
```

That driver requires the disposable profile/skill/provider setup documented in its source. `remaining_product_live_test.dart` additionally uses an owned empty repository through `QA_APPROVAL_REPO` and the dummy vault page in `integration_test/fixtures/vault/`. Do not point destructive approval fixtures at a real project. Serve the dummy page on loopback only. The stock secret-expiry case takes five minutes; a shorter fixture is not equivalent evidence.

For Studio captures, use `--dart-define=STUDIO_REVIEW=true` and the font setup described in the render test. Administration captures use `CAPTURE_ADMINISTRATION` and `CAPTURE_FONT_DIR`. Generated widgets and reserved keyboard insets are not screenshots of an installed app or its actual keyboard.

Connection journey renders use `test/connection_setup_screen_test.dart` with
`--dart-define=CAPTURE_CONNECTION_SETUP=true` and
`--dart-define=CAPTURE_FONT_DIR=<Flutter SDK>/bin/cache/artifacts/material_fonts`.
Captures go under `build/connection-review/`. The transport test uses a disposable
local HTTP/WebSocket server and sends no model message.

The control and layout regression suites export with
`--dart-define=STUDIO_AUDIT_REVIEW=true` and
`--dart-define=CAPTURE_FONT_DIR=<Flutter SDK>/bin/cache/artifacts/material_fonts`.
They cover all five accents, pending/disabled/focus/selection states, and
320 dp layouts at 200% text with reserved keyboard space. Captures go under
`build/studio-audit/`. The native `reading_native_preview.dart` debug target
adds theme/accent switches and locally generated playback, diagram, HTML and
error fixtures. `profile_device_ui_check.dart` supplies clarification retry
and 200% text scenarios with an injected gateway. Restore the normal debug
APK after using either target.

## Recorded live baseline

The 13–14 September 2026 acceptance used local Hermes 0.21.2 at `e16f686706b1e0d5334fd1ae82190058d2a19694`, an Android emulator and disposable data. Separate Samsung and remote-server runs covered selected flows. This dated baseline is useful evidence, not a current certification of every later APK.

| Area | Established result and boundary |
| --- | --- |
| Conversations | Real prompt/reopen, server context, older Find/Outputs, regeneration replacement and separate fork reopen passed. Shared superseded answers have no verified persistence contract. |
| Projects/profile settings | Lifecycle, appearance, description/SOUL, settings readback and cleanup passed. Administration used temporary fields/credentials and MCP fixtures; it did not establish every provider's account approval/inference, SDK installation or backend self-update. |
| Input/approvals | Clarification, sudo/secret cancellation, stock expiry, Deny/Allow once/Session/Always and profile isolation passed. Vault save/cancel forms worked, but correct origin/fill and OTP acceptance remain blocked. External-manager unlock was not configured. |
| Supervision | Goals and default-profile controls passed. Non-default loop scope and unopened child-only Activity reproduced backend gaps. |
| Native files | Real downloaded PDF/image/SVG zoom and WAV/MP3/MP4/WebM playback, seek, pause/return and invalid-format recovery passed. Device codecs/speakers and native HTML behavior need their own coverage. |
| Mobile intake | Samsung picker/camera/share review and recovery checks passed; real image/text contents were checked. Remote file contents and reopen passed via tool read, while automatic `@file` expansion still rejected an out-of-workspace path. |
| Notifications | Local posting/routing plus foreground-service lifecycle checks cover Home, activity destruction/recreation, Doze with battery exemption and stop/restart. Server event gaps and process termination still limit delivery. |

Backend reproductions and closure criteria are retained in [Upstream Hermes bugs](UPSTREAM_HERMES_BUGS.md). App reliability gaps are linked from [Known limitations](KNOWN_LIMITATIONS.md) and the [bug tracker](BUG_TRACKER.md). Retest a reproduced limitation when its relevant contract changes; do not relabel it as a pass to produce an all-green report.
