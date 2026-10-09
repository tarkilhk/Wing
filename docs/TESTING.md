# Testing and acceptance

[Contributing](../CONTRIBUTING.md) covers the toolchain and ordinary analyze/test/build commands. [Windows build workflow](LOCAL_BUILD_SETUP.md) covers cache/lock handling and data-preserving installation. Complete the [release checklist](CODE_QUALITY_CHECKLIST.md) for a fixed release candidate.

## What a passing check establishes

Host unit/widget tests establish client behavior with their supplied responses. An emulator using injected gateways adds Android keyboard, layout and lifecycle evidence. A live-backend driver exercises the deployed contract. A signed phone run adds that device's permissions, native viewers and installation behavior. These results are complementary; none certifies every environment or a Play submission.

Keep logs and generated captures under ignored `build/`. Record source revision, backend revision, device, executed scenario and remaining limit in the PR or issue. Do not create another release-by-release documentation journal. Redact evidence using [Security](../SECURITY.md).

For CPU attribution, input latency, thermal load and battery investigations, use
the [performance procedure](PERFORMANCE.md) and its repeatable phone recorder.

## Verification scope and stopping

Choose checks to resolve an identified risk. Before running them, identify the
changed behavior, affected callers/dependencies, required gates and the condition
that ends verification. Documentation-only edits need review of wording, links
and formatting; they do not need runtime test campaigns.

1. During implementation, run focused tests at the changed contract and the
   applicable source guards. Include affected dependencies when the property
   crosses files or owners.
2. At final integration, run a justified broad suite once for the stable tested
   inputs. Full verification is warranted by changes to checking tools, runners,
   fixtures or dependencies, substantial changes across application boundaries,
   or an explicit release/CI requirement. A local production APK build or phone
   install is not publication and does not itself trigger a full suite.
3. Record the tested revision or source fingerprint, command/scope, configuration
   and result. Reuse that evidence while its relevant inputs remain unchanged.
   A commit, push, equivalent isolated checkout or documentation edit does not
   invalidate unchanged behavior checks. Verify relevant input differences rather
   than treating every new commit hash as a reason to repeat everything.
4. After a failure, diagnose it and rerun the affected test and relevant
   dependencies. For an isolated timeout, check infrastructure/load separately
   from product behavior and rerun that test alone or with lower concurrency.
   A passing isolated rerun closes that uncertainty; it does not invalidate other
   passing checks or justify another full campaign. Preserve the original failed
   aggregate result and report the successful focused rerun separately.
5. Repeat a full suite only when substantial changes invalidate broad evidence,
   failures indicate a wider problem, or an explicit gate requires a fresh run.
   Before repeating it, state the concrete trigger and which evidence is no
   longer usable. A desire for a green aggregate command is not a trigger.
6. Stop when the planned affected checks pass and required gates are satisfied;
   report remaining limits without expanding scope automatically. If the user
   stops testing, terminate the active owned run and start no replacement campaign.
   Continue other authorized work where its prerequisites are satisfied.

When shared app composition adds ongoing I/O, include the affected data consumers
in the verification scope. Exercise nonempty success and recovery through their
production repository/transport seams while the watcher is active. Fixtures must
retain the stock response semantics involved, including exact identity versus
search/lineage resolution. Assert visible results and cleared error states;
header geometry and absence of Flutter exceptions do not establish data health.
Report fixture layout, contract/recovery, live read-only and phone installation
checks separately. A startup PID or screenshot count is not a live feature journey.

Native journeys with ongoing animation use bounded, state-based waits. Keep live
rendering enabled across external screenshot waits when observing motion; an
explicit-pump-only frame policy can discard native timestamps and skip a short
animation after the clock catches up. Check transient notices before capture,
and allow their normal expiry during host I/O. Scroll to unique recovered data
rather than repeated action labels or headings outside a lazily built viewport.

Required published-release and CI gates remain mandatory. A failed or interrupted
full command is not a passing full run; a focused recovery does not waive a gate
that explicitly requires one. For user-requested local phone delivery, reuse
completed checks, build and verify the signed APK, then install it while GitHub
CI runs independently. GitHub CI completion is not a prerequisite for phone
installation. Report its status separately; published-release gates apply to
publication.

## Recents conversation switching

Prerequisite: at least two chats in the selected Recents filter. Open one from
Recents. Exercise the two-finger horizontal swipe and
inward pinch on blank transcript space. Lift both fingers: the stack must remain.
Browse past either end without selecting or resuming a chat, then tap a center or
peek card. The selected normal chat expands, retaining that chat's draft,
attachments and reading position. Back from the stack returns to the entry chat;
Back from the normal chat restores the selected Recents filter. Text selection, code,
Activity controls, pending-input forms, composer and system Back edges must retain
ordinary gestures. Use Chat actions with accessibility enabled. Verify an
adjacent fresh reply cue in both themes, confirmed input amber, suppression while
editing/manipulating and direct settling with reduced motion.

`recent_conversation_session_test.dart` covers frozen scoped identity, circular
policy, bounded physical reads, eviction, cancellation, external selection and
cue admission/coalescing. `recent_conversation_switcher_test.dart` covers real
multitouch, pinch persistence, circular laps, browse/commit, interrupted springs,
pointer-time fling decisions, accessible
controls alongside expert gestures when an accessibility service is enabled,
snapshot-only dragging without preview reads or construction, bounded pixel
ownership/disposal, delayed-resume expansion, removed double-tap switching and
completed asynchronous preview publication,
theme paint and the production Recents route with draft/cursor/Back
restoration at normal and enlarged text in both themes.
`chat_notification_coordinator_test.dart` protects fresh journal projections,
quiet baselines and native-permission independence. Run these plus
`workspace_activity_filters_test.dart` and `profile_ongoing_activity_test.dart`
after changing the entry seam. The standalone application-shell and native preview roots explicitly supply a
read-only activity scope. `streaming_work_budget_test.dart` ensures composer focus
does not rebuild saved messages. For authored fixture render review, run the
switcher suite with `--dart-define=STUDIO_REVIEW=true`; it uses the Studio font
assets under ignored `build/` and exports normal/stack captures to
`build/recents-review/`. Host tests do not certify physical-device gesture feel,
keyboard transitions or frame pacing; inspect those on Android before release.

Recents raster capture runs during idle and waits for the completed paint frame
in every build mode. Physical performance acceptance measures first movement and
frame pacing for swipe, pinch and card browsing on representative rich history.
The controlled repaint case queues a chat rebuild before opening the stack and
checks the captured pixels, so an old frame cannot count as success.
`recent_capture_release_safe_guard_test.dart` also rejects runtime reads of the
actual Flutter debug paint getter, which throws when assertions are disabled.
For a capture change, validate Choose recent conversation and previous/next
conversation from Chat actions in a signed release; debug emulator results alone
do not establish release safety.

For native acceptance, run the isolated API 36 emulator driver:

```sh
python3 scripts/test_native_recents.py --device <emulator-id> --output build/emulator-acceptance/recents
```

It builds `integration_test/recent_conversation_native_test.dart` and compiles a
shell-only Java touch helper. Android dispatches real one/two-finger MotionEvents,
including pinch, double-tap non-admission and interrupted returns; Flutter does not
synthesize these gestures. The matrix uses native normal/200% font settings in
both themes. It covers passive browsing and circular laps, center/peek selection,
keyboard/Back (including hidden-keyboard preservation and menu focus restoration
while the chat is obscured), draft and staged
attachment retention, cross-profile commit/recovery and saved reading offsets,
failed resume recovery,
hidden-card read suppression, neutral/amber cues,
accessible controls and reduced
motion. Screenshots and a gesture video come from the installed Android window.
The driver rejects physical devices and restores its viewport, density and font
settings. Gateways and incoming journal projections are authored observations;
this establishes Android interaction behavior, not live Hermes delivery,
TalkBack usability or physical-device frame pacing. Use `--source-directory` for
an immutable copy when the workspace is changing; keep the tested source hashes
with the private captures. `--name` limits a recovery to the failing case.
Use `--code-only` for independent code-copy/exclusion probes at normal text and
system-edge/drawer Back probes in all four theme/text configurations. Opening
the drawer from a chat and pressing Android Back must close the drawer, retaining
the chat; the next Back restores Recents. These short probes do not replay the
gesture journey or depend on its retained transcript scroll position.

## Connection notice recovery

Switch away and return while the network wakes or automatic retries are active:
no connection health notice or bell issue should appear. Exhaust the recovery
burst with the connection still unavailable: Wing should show “Connection needs
refresh”. Start a fresh retry or restore availability: the connection incident
and its notice should disappear. A chat-only failure with healthy transport stays
local to that chat. Run `server_connection_status_test.dart`,
`profile_workspace_controller_test.dart`, `health_alerts_test.dart` and
`health_alerts_ui_test.dart` for the controlled owner/retry/foreground regressions.
Host tests establish event ordering under supplied failures; they do not establish
physical-device network timing.

## Bots

Open the drawer → Bots. Verify Bots/Groups tabs, one continuous list with pins
first, the pin glyph, canonical last-message truncation, search and live filters.
Tap the avatar to open Edit name & appearance without opening chat; tap the
name/message area to open chat. Avatar actions have accessible labels and 48 dp targets. The bot row menu
contains only View screen, Pin/Unpin, Hide/Show and Bot settings. In Bot settings,
verify appearance, duplicate, Advanced → Rename profile and the bottom delete
confirmation, including the protected default profile. Back from an appearance
edit and reopen it: the acknowledged values must remain. Confirmed rename/delete
must retire the old settings route on return from profile management.
Open a bot and use Back: the original tab, query and filter must remain. Open a
bot from another saved instance: the secure workspace identity must match the
captured row before opening its chat. Change appearance, then open Bot
settings and exercise the existing identity/model/account/capability editors.
Verify that a concurrent desktop edit requires reload/review, and that partial
saves retain the remaining draft without repeating acknowledged sections.
Appearance has no confirmation tick: valid edits autosave after typing pauses,
and Back flushes pending changes. Reload saved appearance must succeed silently,
preserve edited fields and adopt fresh untouched fields. A real write failure
keeps the draft and exposes retry; a conflict requires reload/review. Back asks
about discarding only when pending changes cannot be saved.

Create a hosted Discussion group with 2–6 bots on a ready instance. Send a
message, mention a member, inspect one-time approval/deny, stop, rename and
disband controls. A lost send acknowledgement must retain the same event ID
and text for Retry. Inspect real screen previews, including the human-control
privacy suppression. See [the current contract and limits](BOTS.md).

`bots_contract_test.dart` covers stock wire shapes, ownership, CAS, canonical
creation/title races, coalesced autosaves, edits during writes, silent reload,
conflict review, retired timers, partial saves, command admission and idempotent sends.
`bots_view_test.dart` covers the production drawer/chat/Back journey and native
roster, menus, creation and appearance/settings reachability at 390 dp/100%
and 320 dp/200% in both themes. Run it with `--dart-define=STUDIO_REVIEW=true`
to export actual Flutter captures to ignored `build/bots-review/`. The isolated
LAN review uses those production views with authored sample data; it never
connects to a Hermes server. These checks do not certify a live provider's
image generation or a physical phone's screen control.

For the limited Android form/navigation gate, request a free owned emulator slot
from the shared coordinator, then run:

```sh
flock /home/dev/projects/hermes-android/.session-coordination/execution.lock python3 scripts/test_native_bots.py --device <allocated-emulator> --output build/emulator-acceptance/bots
```

The driver rejects physical devices, restores viewport/density/system font scale,
and injects actual Android text and Back events. The four light/dark,
390 dp/100% and 320 dp/200% cases cover drawer/chat/Back and retained search,
appearance autosave/Back, Android document-picker cancellation, profile settings,
new-bot creation and exact group-send recovery. Screenshots come from Android's
window. Only stock transport observations are authored; provider generation,
real display control and live Hermes delivery remain separate checks. The builder
owns APK assembly; keep this dependent command sequence under the shared lease.
Use `--source-directory` for its frozen checkout and `--name` for a failing case.

## Continuous checks

After activating the Flutter toolchain, run `python3 scripts/test.py` for routine
verification. This includes product unit/widget tests, security, recovery,
ownership, accessibility and work-budget regressions, plus every current-source
Dart and Python/native linter through `scripts/check_commit_linters.py`.
Routine linters and host tests run concurrently; both must finish successfully
for the command to pass.
The exhaustive tests of the architecture checking tools are retained in the
explicit `architectureProofSuites` inventory in `tools/testing/test_batches.dart`.
They run in `python3 scripts/test.py --full`, which executes every discovered
`test/**/*_test.dart` main once. The two mixed scheduled-task contract suites
retain all their actual repository/DTO and fixture checks in routine runs.
New unclassified suites run routinely; they are never silently scheduled away.

| Check | Cadence |
| --- | --- |
| Source linters | Every local commit with the hook installed, every branch push/PR, and release |
| Product host tests | Every routine run and branch push/PR |
| Complete checker fixtures and source/native/SDK proofs | Nightly, whenever checking tools/runner/fixture/dependency inputs change, and before a published release |

CI uses `--changed-since` with the preceding commit or PR base to select full
verification when tool inputs change. Unknown or missing history selects the
full suite. The nightly workflow also supports manual dispatch. Scheduling
preserves every test but can delay finding a checking-tool regression until the
next full run; checking the current app source is never deferred.

CI runs the Dart source checks together with
`python3 scripts/check_commit_linters.py --dart-only`, preserving each rule while
sharing startup and analysis work. PR checks also bind the aggregate to the
preceding architecture baseline with `--baseline-reference`. Python source
checks run explicitly, and native source guards run after Gradle has supplied
their compiler dependencies. PR host tests use `scripts/test.py --skip-linters`
because these mandatory workflow steps enforce the linters separately. The
workflow guard requires the Dart source gate before that host step and Gradle
setup before each native gate. Local routine verification keeps all linters.
Python runner tests prove source-check discovery, baseline handling, failure
propagation and separation of native dependencies; they run in both workflows.

Ordinary suites share generated Flutter
batches, with separate lanes for pure tests, widget bindings and reviewed
architecture wrappers. Additional transport fixtures require a source and
cleanup review before batching. Custom bindings, font loading, special
performance/cache lifetimes, environment-gated suites and unscoped setup stay
isolated. Architecture fixture and CLI children retain fresh processes. The runner
checks the complete selected/scheduled partition and source fingerprints, propagates any test failure,
and retains its plan, machine events and toolchain metadata in a private
owner-only temporary directory outside the checkout. During full runs, architecture guard and
fixture programs are compiled together to a native AOT snapshot from the current
source once during the timed run. Each selected main executes in a fresh SDK
native runtime process with its original arguments and diagnostic assertions.
The runtime stays inside the selected SDK so implicit SDK discovery retains
its source-run provenance. Native AOT compilation and SDK
controls retain their original independent subprocesses. Compilation or an
unknown command fails verification. Generated code is removed after execution.
`--concurrency=N` controls the shared host worker limit;
the default is at most eight. Focused checks still use `flutter test --no-pub`
with their original file paths. Device and live acceptance remain explicit.

PRs and pushes to `main` run Dart analysis, host Flutter tests, a debug Android
APK build, and native JVM boundary tests. Android checks use Flutter 3.44.0,
Temurin Java 17, SDK platform 36, build-tools 36.0.0 and the project's pinned
Gradle distribution. The debug build uses the development application ID and
Android's generated debug key; it requires no production signing secrets.
Native JVM tests exercise the actual notification identity and shared-content
URI boundary code, but do not emulate Android intents, permissions or WebView.

After `flutter pub get` and `flutter build apk --debug --no-pub`, run the JVM
tests from the checkout root:

```sh
./android/gradlew -p android :app:testDebugUnitTest --no-daemon
```

The Flutter build prepares the local Android wrapper and SDK properties for a
fresh checkout. Run Android builds and tests sequentially.

After native integration runs, use `flutter build apk --release` with its
normal pub step. Using `--no-pub` across that mode change can retain the
integration-only generated plugin registrant while the release dependency graph
excludes that plugin. The release script and workflow already omit `--no-pub`;
regenerate through the supported build command rather than adding a test plugin
to the production dependency graph.

A separate PR job runs the actual Mermaid/SVG/HTML isolation harness using
Node 22.23.3, locked Playwright Core 1.58.2 and its pinned Chromium. The release
workflow reuses the same renderer action and runs native JVM tests before APK
publication. Both fail on test errors. Follow the reproducible commands in
[Diagram previews](DIAGRAM_PREVIEWS.md#verification-after-an-update); browser
checks establish desktop Chromium enforcement and require separate Android
WebView acceptance on a disposable emulator.

## Useful test entry points

`INLINE_SKILL_COMPOSER` is guarded by `test/slash_commands_test.dart`: a slash after prose or a newline opens a skill-only helper; selection replaces just the token at a UTF-16 cursor, keeping the suffix and saving the exact draft. Catalog-confirmed skill emphasis retains plain text, IME underline and scope retirement. Inline sending uses stock skill dispatch, retains the visible message and preserves queued work on load failure; commands, URLs and paths in prose stay literal. Run the suite after composer/slash changes. The production screen cases cover 390 dp at ordinary text and 320 dp at 200% in both themes; `CAPTURE_SKILL_COMPOSER=1` exports actual Flutter captures under ignored `build/skill-composer/`, with optional `CAPTURE_SKILL_COMPOSER_FONTS` pointing at the SDK's material font directory. Static checks cannot establish cursor replacement, styled text editing or asynchronous callback admission. Host captures do not establish physical Android keyboard behavior.

`integration_test/slash_completion_native_test.dart` covers the production composer on a disposable Android emulator in both themes at ordinary and 200% text. Use `--no-uninstall`. Its optional `SLASH_NATIVE_INPUT=true` checkpoints allow a host driver to resize the emulator to 390/320 dp, inject Android typing/backspace events and take native screenshots with the keyboard visible. Read the stage's name/token from the app's `Directory.systemTemp` `wing-slash-stage.json`, perform the indicated action, then write that token to `wing-slash-ack` in the same directory; each checkpoint is bounded to 30 seconds. Picker/selected/suffix checkpoints require screenshots and a positive Android IME-visible observation. The test checks exact draft text, bold/accent spans, retained suffix/cursor, editable skill text and absence of prompt submission. This uses an injected stock-contract gateway and establishes Android input/layout behavior, without contacting a live Hermes server or consuming model requests.

`SAVED_TOOL_RUN_BOUNDARY` is guarded by `test/profile_design_test.dart`:
invisible empty assistant rows separate neighboring tool runs, while explicitly
hidden rows retain continuity. Saved tools/reasoning can join live Activity;
final reviews keep live work and their own detail action reachable. Mounted
regressions cover both live tools and reasoning after a final review.
Native reasoning-only rows remain visible through
the saved projection regressions in `test/profile_execution_activity_test.dart`.
These checks establish grouping semantics and rendered expansion; source shape
alone cannot establish which immutable rows a projection publishes.

`CONVERSATION_TIMING_DISPOSAL` is guarded by
`test/profile_execution_activity_test.dart`: throttled completions in two chats
survive shutdown alongside older measurements outside the 60-row preview,
including a received zero duration. Disposed readings reject new receipts and
publication; confirmed deletion cannot resurrect its timing index. The snapshot
suites separately cover ordered writes, preview limits and unchanged workspace
work budgets. Static disposal order alone cannot prove retained revisions or
what later asynchronous batches persist.

`BROWSER_FILTER_PUBLICATION` is guarded by `test/chat_browser_data_test.dart`
and `test/chat_list_target_test.dart`. Canonical bulk refreshes publish when a
row enters or leaves the confirmed Unread/Draft filter or local title/preview
query; the mounted browser removes and restores the row without replacing its
State. Stable membership remains a row-only update, with no extra index read or
list publication. Static ownership guards cannot establish reactive membership
or observer delivery.

`MODEL_CHOOSER_KEYBOARD` is guarded by `test/model_chooser_test.dart` and the
shared `test/studio_selection_test.dart`. Arrow keys traverse ordinary and named
special choices; Tab reaches the separate info action and Space opens it without
selecting another model. Disabled controls retire focus and reject writes.
Narrow light/dark layouts retain compact pricing and background-only selection
at normal and enlarged text. Static construction checks cannot establish focus
traversal or keyboard event delivery. Existing picker caller suites retain their
captured edit/persistence behavior.

`TEST_FIXTURE_ENDPOINT_ROUTING` is guarded by
`test/chat_browser_mutations_test.dart` and
`test/profile_workspace_controller_test.dart`. Browser fixtures route GUI-log
reads independently of held chat-list pages and reject unmodeled endpoints.
Profile-owned REST reads and every RPC retain their captured profile; timing
recovery's process GUI-log request must instead carry exactly `file: gui`, the
saved chat's search identity and `lines: 500`, without a profile override.
Verified against stock Hermes main
[`08165d58931841cee713468ae89032af7c57060a`](https://github.com/NousResearch/hermes-agent/commit/08165d58931841cee713468ae89032af7c57060a),
whose `hermes_cli/web_routers/status.py` resolves an omitted profile to the
dashboard's log directory. Behavioral checks own this invariant because source
patterns alone cannot establish which held I/O a fixture awaits or the request
parameters sent through the actual controller path. Run
`flutter test --no-pub test/chat_browser_mutations_test.dart test/profile_workspace_controller_test.dart`.

The deletion cases in `test/chat_browser_actions_test.dart` and
`test/profile_row_actions_test.dart` guard `BROWSER_DELETE_ASYNC_CLEANUP`.
Confirmed deletion waits for ordered timing-cache writes, including background
isolate encoding. The widget harness alternates real async work with frame pumps
until the captured chat's mutation finishes, then settles the confirmation route.
The original assertions still require deletion and unlocked controls while
follow-up chat-list reads are held. Static checks cannot establish isolate
completion or fake-async scheduling; these behavioral cases cover both.

For the Chats Project filter, run `flutter test --no-pub test/chat_browser_data_test.dart test/chat_list_target_test.dart`. Select a profile using the header squares or Profile menu, then open Project: only that profile's projects and unassigned-chat group should appear. Multiple selected profiles expose their combined choices; clearing Profile restores all choices. The owner regression checks membership with repeated project IDs across profiles; widget regressions cover switching and clearing in both themes at normal and 200% text. This dynamic membership property uses behavioral checks rather than a source linter.

For ordinary-app startup acceptance, install the normal debug APK on a fresh
disposable emulator, then deny Notifications and Microphone in Android's actual
permission dialogs. Confirm the welcome screen and connection setup remain
usable. Force-stop only `com.tarkilhk.wing.dev`, launch it again, and verify both
permissions remain denied without repeated prompts. Capture the rendered welcome
and setup screens. This uses the production entry point, without a fixture APK;
a previous integration target's settings are not a fresh-install test. Never
clear a personal installation to obtain this state.

For Android task reentry, run
`python3 tools/qa/check_activity_reentry.py --serial <device-id> --package <installed-package>`
on an unlocked device. It restarts Wing without clearing data, opens the Recents
shortcut with a competing-task launch flag, and resumes the original task three
times. It checks that the app content renders, the same activity and task are reused, and
Android Recents contains exactly one Wing card, including after a restart. This
native check covers engine eviction, which host widget tests cannot reproduce.
It navigates the real app but does not send messages or modify settings.

| Boundary | Entry points |
| --- | --- |
| Ownership and administration | `test/administration_*_test.dart`, `test/profile_live_contract_test.dart`, `integration_test/administration_existing_server_live_test.dart` |
| Provider recovery | `test/provider_console_test.dart`, `test/provider_recovery_test.dart`, `test/provider_recovery_screen_test.dart`, `test/workspace_picker_test.dart` |
| Notification destination recovery | `test/profile_notification_recovery_test.dart`, `test/workspace_connection_failure_test.dart`, `test/server_connection_status_test.dart`, `test/workspace_reading_snapshot_test.dart` |
| [Draft/outbox lifecycle](DRAFTS_OUTBOX.md) | `test/composer_draft_record_work_test.dart`, `test/conversation_outbox_lifecycle_test.dart`, `test/conversation_outbox_screen_test.dart`, `test/profile_composer_queue_test.dart`, `test/profile_queue_submission_ownership_test.dart`, `integration_test/profile_lost_ack_live_test.dart` |
| Native queue editing | `integration_test/queued_message_edit_test.dart`, `integration_test/queued_message_native_preview.dart` |
| Saved history and branches | `test/answer_sync_acceptance_live_test.dart`, `test/profile_live_history_test.dart`, `integration_test/answer_branch_live_test.dart` |
| Sensitive input, goals and projects | `integration_test/backend_acceptance_live_test.dart` and its profile-specific companion drivers |
| Vault, approvals, loops and child-only work | `integration_test/remaining_product_live_test.dart` |
| Notifications | `test/chat_notification_test.dart`, `test/plugin_turn_notification_sink_test.dart`, `test/profile_notification_live_test.dart`, `test/profile_notification_coverage_test.dart`, `integration_test/profile_notification_test.dart`, `tools/qa/check_background_monitoring.py` |
| Launcher shortcuts | `test/android_launcher_shortcut_contract_test.dart`, `test/android_launch_intent_service_test.dart`, `test/home_config_restore_test.dart`, `tools/qa/check_launcher_shortcut.py` |
| Slash profile scope | `test/slash_profile_live_contract_test.dart`, `integration_test/slash_commands_live_test.dart` |
| Configuration backup | `test/config_backup_service_test.dart`, `test/config_backup_test.dart`, `test/home_config_restore_test.dart`, `integration_test/config_backup_native_test.dart` |
| Connection setup | `test/connection_address_test.dart`, `test/connection_setup_probe_test.dart`, `test/connection_setup_transport_test.dart`, `test/connection_setup_screen_test.dart` |
| Scheduled tasks | `test/scheduled_tasks_*_test.dart`, `integration_test/scheduled_tasks_native_test.dart` |
| Voice | `test/voice_*_test.dart`, `test/profile_voice*_test.dart`, `test/hermes_voice_test.dart`, `test/microphone_permission_test.dart`, `test/startup_notification_permission_test.dart`, `integration_test/voice_*_test.dart`; [profile voice checks](PROFILE_VOICE.md#verification) |
| Context occupancy and composition | `test/context_ring_test.dart`, `test/profile_context_usage_test.dart`; render with `--dart-define=CONTEXT_RING_REVIEW=true` and the existing `build/studio-roboto.ttf` / `build/studio-icons.otf` review fonts. Captures and ring coordinates go to ignored `build/context-ring-review/` for pixel inspection |
| Design renders | `test/studio_layout_test.dart`, `test/studio_controls_test.dart`, `test/studio_layout_regressions_test.dart`, `test/administration_navigation_test.dart` |
| [Accepted activity family](DESIGN_SYSTEM.md#accepted-activity-detail-family) | `test/activity_family_test.dart` extends real-font review to Tasks, saved/live Agents, Work, goals, reasoning, search, writes and web results (`CAPTURE_ACTIVITY_FAMILY=true`). `test/profile_tool_call_test.dart` compares visible content/icon edges, compact toolbar height, neutral completion footers and retained actions across code/read/edit/vision in both themes at ordinary and enlarged text. Capture with `CAPTURE_TOOL_RESULTS=true` and actual review fonts as described in [tool activity verification](TOOL_ACTIVITY.md#inline-requests-and-receipts); inspect the family together |
| Health alerts, shared headers, populated Recents and Analytics recovery | `test/health_alerts_test.dart`, `test/health_alerts_ui_test.dart`, `integration_test/health_alerts_native_test.dart` on a disposable Android emulator; [capture and contract](ADMINISTRATION.md#health-alerts) |
| Host resources and reusable alert inputs | `test/host_resources_session_test.dart`, `test/host_thresholds_test.dart`, `test/host_health_view_test.dart`; render with `CAPTURE_HOST_HEALTH=true` and `CAPTURE_FONT_DIR=<Flutter SDK>/bin/cache/artifacts/material_fonts` into ignored `build/host-health/` |

Read a driver's environment flags, mutations and cleanup before running it. Use disposable profiles/chats and owned fixtures on an authorized server. Live tests may invoke models, modify profile settings or start host tools. Restore changed values and independently verify cleanup; a green assertion that records `backend_limited` is not successful feature acceptance.

For an existing password-protected dashboard, the read-only host checks use
normal sign-in, profile discovery, scoped administration catalogs and a
single-use WebSocket ticket with liveness/capability RPCs. Put `username` and
`password` in a temporary JSON file outside the repository with mode `0600`,
then provide its path at runtime:

```bash
WING_HERMES_URL='https://<dashboard-host>' WING_HERMES_LOGIN_FILE=/path/to/private-login.json flutter test --no-pub test/existing_backend_readonly_live_test.dart
```

The corresponding installed Android journey reads its credential file from
the disposable emulator's private app cache. Install the development package
first, copy the file into its cache using `adb shell run-as com.tarkilhk.wing.dev`,
and run:

```bash
flutter test --no-pub integration_test/administration_existing_server_live_test.dart -d '<emulator-id>' --no-uninstall --dart-define='WING_HERMES_URL=https://<dashboard-host>' --dart-define=WING_HERMES_LOGIN_FILE=/data/user/0/com.tarkilhk.wing.dev/cache/wing-hermes-login.json
```

Only the URL and file path enter Dart defines; credentials remain runtime data.
Remove both temporary credential files after the run, including on failure.
The journey opens Administration and Versions & updates, verifies the reachable
Hermes health drawer entry, then closes the drawer without entering Health.
Health entry automatically starts missing/expired Doctor and security-audit
operations and profile checks, so its interactive coverage belongs to the
isolated native fixtures. These existing-server checks create no chats, invoke
no models and change no profile settings or server operations.

`integration_test/existing_server_chat_probe_test.dart` is a separate optional
model test, disabled unless `--dart-define=RUN_MODEL=true` is supplied. Obtain
explicit approval for its model/backend side effects before enabling it. It uses
the same runtime URL/credential-file defines, creates one owned QA chat, sends
one prompt, and deletes only that exact chat after confirmed idleness. It does
not change shared profile settings or accept pending approvals. Current stock
has no per-chat toolset override, so the test inherits the profile's tools,
context and memory; the prompt's instruction cannot guarantee zero tool calls.
Read its cleanup guards and limits before execution.

After installing an APK on an emulator, run `python3 tools/qa/check_launcher_shortcut.py --serial <emulator-id> --package com.tarkilhk.wing.dev` (use `com.tarkilhk.wing` for release or signed development builds). This read-only check verifies Android's registered Quick Chat, Activity and Search chats intents and resolves their activity. Gradle generates `xml/shortcuts.xml` from `android/app/src/main/shortcuts.xml.template` using each variant's application ID; intent targets must be literal package names because Android parses them with system resources. Flutter tests cover the subsequent cold/warm launch handoff, destination routing, search focus and draft preservation.

Configuration backup's native test runs with
`flutter test integration_test/config_backup_native_test.dart -d <emulator-id> --no-uninstall --dart-define=CONFIG_BACKUP_NATIVE=true`.
For an automated emulator run, use
`python3 scripts/test_native_config_backup.py --device <emulator-id>`.
The driver builds a disposable SDK-only share receiver, starts the Flutter test,
selects that receiver in the actual Android share sheet, saves to Downloads through
DocumentsUI, and selects the saved document for every restore attempt. It compares
saved bytes with the real exported cache file and removes its helper and owned
files afterward. XML, screenshots, Flutter logs and acceptance results go under
`build/native-backup-review/`; SDK 36/JDK 17 paths can be passed explicitly.
Use a disposable emulator with a local file-saving share target. At each share
sheet, save the file to Downloads; at each document picker, select the file just
exported. Flutter drives the app's dialogs, including the wrong-passphrase
attempt. The test's `backup-qa-stage` file in the app's external files directory
identifies each native step for a host UI driver. It uses isolated real Android
preferences and Keystore namespaces, synthetic connection credentials and no
backend. Coverage includes plain Merge, encrypted Replace, restored settings in
the current screen, and persisted credentials read through a new storage client.

For native file/photo selection and cancellation plus outgoing share-sheet
cancellation, run
`python3 scripts/test_native_file_transfer.py --device <emulator-id> --output build/native-file-transfer-review`.
The driver uses synthetic owned files, runs seven Flutter tests while handling
six native picker/share steps, and verifies owned file/cache cleanup. For the
separate inbound URI boundary, build/install the isolated notification QA target
above, launch it with empty native intake, then run
`python3 tools/qa/check_external_share.py --serial <emulator-id>`.
Its SDK-only foreign-UID helper tests file/self-provider origins, missing read
grants, mixed batches and exact granted bytes without opening rejected providers.

For a compatible local backend/emulator, the basic connection pattern is:

```text
adb -s <emulator-id> reverse tcp:<port> tcp:<port>
flutter test integration_test/backend_acceptance_live_test.dart -d <emulator-id> --no-uninstall --dart-define=HERMES_TEST_PORT=<port>
```

That driver requires the disposable profile/skill/provider setup documented in its source. `remaining_product_live_test.dart` additionally uses an owned empty repository through `QA_APPROVAL_REPO` and the dummy vault page in `integration_test/fixtures/vault/`. Do not point destructive approval fixtures at a real project. Serve the dummy page on loopback only. The stock secret-expiry case takes five minutes; a shorter fixture is not equivalent evidence.

`integration_test/profile_expansion_scroll_test.dart` runs transcript expansion,
collapse without leftover bottom gaps, search, pagination/retry, reading anchors
and streaming follow/reading regressions
on Android with local gateways. Run it on the disposable emulator with ordinary
`flutter test --no-pub ... -d <emulator-id> --no-uninstall` flags. It writes PNG captures to the development package's external files directory;
pull and inspect normal/enlarged text in both themes. Native interaction tests and their captures do not measure frame/input
latency or model streaming from a live server.

For broad installed-app journeys through chats/projects, input and approvals,
context usage, administration/Identity, versions, health, provider access and
answer branches, run:

```sh
flutter test --no-pub integration_test/roadmap_emulator_test.dart -d <emulator-id> --no-uninstall --dart-define=JOURNEY_THEME=light --dart-define=CAPTURE_JOURNEYS=true
```

`--no-uninstall` is required to retain the captures after the test ends. Copy
all paths printed as `Journey frame` from the development package's code cache
before any next install, then repeat with `JOURNEY_THEME=dark` and copy that set.
A new install can also clear code cache. The suite uses local gateways, populated
usage data with unknown/partial annotations, stock-shaped Doctor/Audit fixtures
and intentional incomplete profile checks. It sends no live backend operations;
fixture success does not establish actual provider/health operation access.

For Studio captures, use `--dart-define=STUDIO_REVIEW=true` and the font setup described in the render test. Administration captures use `CAPTURE_ADMINISTRATION` and `CAPTURE_FONT_DIR`. Generated widgets and reserved keyboard insets are not screenshots of an installed app or its actual keyboard.

The Studio renderer sets actual view metrics at DPR 1 and checks the inherited
viewport width. Its conversation fixture loads saved history and model metadata
through the controller's normal reads, then sends a context-usage event. Before
exporting, it asserts the title, assistant content, absent empty greeting and
the appropriate inline or stacked scope header. The Teal phone captures cover
360×800 dp at normal text and 320×800 dp at 200% in both themes:

```sh
flutter test --no-pub --dart-define=STUDIO_REVIEW=true test/studio_layout_test.dart --name '(light|dark) mint at width (360.0|320.0)'
```

Connection journey renders use `test/connection_setup_screen_test.dart` with
`--dart-define=CAPTURE_CONNECTION_SETUP=true` and
`--dart-define=CAPTURE_FONT_DIR=<Flutter SDK>/bin/cache/artifacts/material_fonts`.
Captures go under `build/connection-review/`. The transport test uses a disposable
local HTTP/WebSocket server and sends no model message.
The 320×640 dp journey includes the Custom setup chat address in empty, focused,
filled and invalid states at 100% and 200% text in both themes. Run that capture
matrix with `--name 'journey fits 320dp'`.

Scheduled-task renders use `test/scheduled_tasks_screens_test.dart` with
`--dart-define=CAPTURE_SCHEDULED_TASKS=true` and
`--dart-define=CAPTURE_FONT_DIR=<Flutter SDK>/bin/cache/artifacts/material_fonts`.
This renderer loads the SDK's case-sensitive `Roboto-Regular.ttf` and
`MaterialIcons-Regular.otf` files. Captures go to `build/scheduled-tasks-review/`.
It covers both themes, all five accents, and 320 dp at 200% text. The native
integration driver uses production screens with an in-memory transport on a
disposable emulator; it does not contact a real agent.

`test/scheduled_tasks_live_test.dart` is separately opt-in via
`--dart-define=SCHEDULED_TASKS_LIVE=true`. It targets loopback port 9847 (override
with `SCHEDULED_TASKS_PORT`) using the normal local dashboard handshake. Start
the unchanged Hermes server with an isolated disposable `HERMES_HOME`, a
`mobile-test` profile, and `scripts/probe.sh` inside that profile containing only
`printf 'Scheduled task acceptance passed\n'`. Headless Hermes serves the local
token handshake without a web build. The driver creates paused agent tasks,
runs only the harmless script task, briefly creates/pauses a template, then
deletes and verifies removal of its owned jobs. Do not use a production data
directory. This establishes scheduling API and script execution behavior; it
does not establish paid model inference or external messaging delivery.

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

Deliverable card renders use `test/deliverable_attachment_test.dart` with
`CAPTURE_DELIVERABLES=true` and the same `CAPTURE_FONT_DIR`. Captures cover both
themes at 320 dp with normal and 200% text under `build/deliverables-review/`.
The offline debug target `integration_test/deliverables_native_preview.dart`
uses production cards, the reader and Android's save picker with a synthetic
Markdown report. Check Rendered/Source, Back, save/cancel and the saved bytes;
restore the normal debug APK afterward. This establishes native UI and file
delivery behavior, not access to a live server's files.

Large HTML checks use `scripts/test-diagram-preview.mjs` with the
[pinned browser test setup](DIAGRAM_PREVIEWS.md#verification-after-an-update)
to render and interact with 2, 8 and 32 MiB documents and verify isolation.
The offline Android debug entry point
`integration_test/large_html_native_preview.dart` opens a complete 32 MiB fixture
through the production HTML screen. Build it for a disposable emulator, install
with `adb install -r`, and launch `com.tarkilhk.wing.dev`.
Forward a local port to that app process's `webview_devtools_remote_<pid>` socket,
then run `WING_ADB_SERIAL=<emulator-id> WING_CDP_ENDPOINT=http://127.0.0.1:<forwarded-port> node scripts/check-large-html-native.mjs`
with Node 22. The harness connects directly to that WebView page's debug socket;
it uses the parent and report's existing default execution contexts, without
creating browser contexts or granting cross-origin access. It verifies content
at the end of the full document, sends a real input click to a report control,
checks the sandbox and parent/storage isolation, and captures the actual WebView
under `build/large-html-review/`. Network checks create an owned bounded ADB
reverse to a loopback HTTP probe: the same emulator must receive a complete
HTTP 200 control response, while the sandbox's fetch/image probes must fail with
enforced connect-src/img-src violations and zero probe-server hits. A successful
run writes `native-http-isolation.json` alongside the screenshot. It rejects
physical-device serials and removes its owned reverse; remove the CDP forward
afterward. This proves fixture behavior, not access to the user's real report. Restore the normal debug
APK after using the fixture on a persistent development device.

## Voice acceptance

Voice host tests cover all four Local/Hermes input/output combinations, preference
persistence and failed saves, profile-scoped authentication, stale callbacks,
permissions, draft insertion without sending, read-aloud prose, and cancellation.
For automated offline emulator acceptance, run
`python3 scripts/test_native_voice.py --device <emulator-id> --output build/native-voice-review`.
Install the development package first. After a cold boot, verify that the
launcher responds and Android has no crash/ANR dialog before starting a build.
`sys.boot_completed=1` alone does not establish responsive UI while Android
startup work is settling. Recover an unhealthy disposable emulator before
rerunning; retain the failed result and keep the driver's ANR checks intact.
The driver rejects physical devices,
resets only that package's microphone permission flags, handles the actual
Android deny/grant dialogs and Home cancellation, then runs native recording,
playback and installed offline TTS tests sequentially. It records capabilities,
callback timings, screenshots and cache cleanup; it does not establish speech
quality or exercise Hermes voice providers.

Run settings/composer renders with `--dart-define=VOICE_REVIEW=true` and
`--dart-define=CAPTURE_FONT_DIR=<Flutter SDK>/bin/cache/artifacts/material_fonts`.
Inspect `build/voice-review/` in both themes at 320 dp and 200% text.

On a disposable emulator with microphone permission granted, run
`flutter test integration_test/voice_native_test.dart -d <serial> --no-uninstall`.
It exercises real AAC recording, cancellation, MediaPlayer decoding/interruption,
and five offline TTS samples when an offline voice is installed. It reports TTS
start-callback timing, not measured speaker latency. Verify `cache/voice` is empty
afterward using `adb -s <serial> shell run-as com.tarkilhk.wing.dev ls cache/voice`.
Restore the normal debug APK after using the integration target.

`integration_test/voice_permission_native_test.dart` exercises Android's real
denial, retry/grant and background cancellation. On a disposable emulator, revoke
`RECORD_AUDIO` and clear its `user-set`/`user-fixed` permission flags before running
the driver. Follow its printed markers: deny the first dialog, grant the second,
then press Home after `VOICE_BACKGROUND_READY`. The driver expects the recorder
to stop and its file to be removed; resume the app to finish the test.

Complete separate human/native and live-provider acceptance before claiming voice
quality or full feature validation:

- On a fresh disposable install, decline notifications, then microphone. Confirm
  startup works, relaunch does not repeat either prompt, and tapping Dictate can
  request microphone access. Check denial and subsequent grant.
- Use a compatible server/profile with transcription and synthesis configured.
  Record the server revision, phone/Android version, installed voice and language,
  and provider names. The app must send no per-request remote voice override.
- Try Local/Local, Local/Hermes, Hermes/Local and Hermes/Hermes. For each input
  engine, dictate at least five samples: a short request, a longer paragraph,
  punctuation, names/numbers, and speech with background noise. Record original
  wording, returned text, corrections needed, and end-of-speech-to-final-text time.
- For each output engine, listen to at least five replies, including long prose,
  punctuation, names/numbers and Markdown/code. Check intelligibility and record
  request-to-first-audible-speech time. Android TTS callback timestamps alone do
  not establish intelligibility or audible latency.
- During capture, transcription, synthesis and playback, cancel, switch chats or
  profiles, and background the app. Verify no stale draft insertion or late audio.
  Interrupt playback with audio focus loss/headphone removal. Exercise unavailable
  local languages/voices and remote provider/network failures. Check drafts and
  temporary-file cleanup; process-death leftovers are cleared on next app launch.

Synthetic tones and mock transcripts do not satisfy these speech-quality checks.

## Administration checks

The administration fixtures establish UI
behavior without contacting real profiles, speech providers or service accounts.

```bash
flutter test test/administration_overview_test.dart test/administration_runtime_health_test.dart test/administration_comparison_test.dart test/administration_editor_experience_test.dart test/administration_navigation_test.dart
flutter test --dart-define=CAPTURE_ADMINISTRATION=true --dart-define=CAPTURE_FONT_DIR=/path/to/fonts test/administration_design_test.dart test/administration_navigation_test.dart
flutter test integration_test/administration_native_test.dart -d <disposable-emulator> --no-uninstall
```

The capture font directory contains `roboto-regular.ttf` and
`materialicons-regular.otf`. Actual Flutter captures are written to ignored
`build/administration-preview/`; the integrated project-picker test retains its
own capture switch and directory. The matrix includes twelve detail/editor
families in light/dark, 320 dp at 200% text, a standard phone and an 840 dp layout;
root checks cover all five accents, populated profile briefs and explicit attention
states. Runtime captures include retained results and supported next steps. Pending/unconfirmed settings and partially
applied Identity writes use explicit fixture responses.

Native tests exercise a semantics tap, the actual Android keyboard, deliberate
remote-conflict resolution, discard protection, long Identity drafts,
profile-owned provider defaults, independent capability disclosure/toggle actions,
48 dp target edges and keyboard focus. A fourth journey runs a fixture Doctor, returns to the
retained failed observation, and reviews the same operation without another POST. `CAPTURE_NATIVE_ADMINISTRATION=true` adds a ten-second
capture point after the capability checks for external `adb` screenshot/tree
collection. This is fixture-based Android interaction evidence, not certification
of a live backend, every installed screen reader or production account access.

## Notification checks

The production notification path has an isolated emulator fixture:

```sh
ORG_GRADLE_PROJECT_notificationQa=true flutter build apk --debug --target-platform android-x64 -t integration_test/notification_revamp_device.dart
adb -s emulator-5556 install --no-incremental -r -g build/app/outputs/flutter-apk/app-debug.apk
python3 tools/qa/check_notification_revamp.py --serial emulator-5556
```

After the main notification journey, run
`python3 scripts/test_native_notification_restore.py --serial <emulator-id>`
against the same QA APK to check force-stop restoration, actual reply tap/read,
and persisted read/dismiss state. The script resets only the QA package and
creates a local forward on port 18767 by default; remove that owned forward
afterward, including on failure. For collapsed/expanded counts and hidden-preview
privacy, launch the QA fixture, forward a local port to `tcp:18766`, then run
`python3 scripts/test_native_notification_counts.py --serial <emulator-id> --port <forwarded-port>`.
Remove that owned forward afterward.

The main driver resets only `com.tarkilhk.wing.notificationqa`, rejects non-emulators,
uses fake Hermes transport data, and restores normal font size/light theme. It
checks rejection of forged/raw/wrong-type exported-activity inputs, FIFO approval
identity, failed submission retention, Always confirmation,
privacy Review, watcher-only remote resolution, latest-reply reading, and native
100%/200% layouts in both themes. Screenshots are in `build/notification-review/`.

For the first pending-input notification from a cached chat that has never been
opened, build `integration_test/notification_cold_input_device.dart` with the same
`ORG_GRADLE_PROJECT_notificationQa=true` QA variant, install on the disposable
emulator, and launch the QA activity. Run
`python3 scripts/test_native_cold_notification.py --serial <emulator-id>`.
It verifies the full question count/text/options, Review, fresh-alert flag and
monitoring shutdown using synthetic data. Remove its owned ADB forward and stop
the QA fixture after the run, including on failure.

For manual checks against stock Hermes, generate supported notification events one scenario at a time. Record backend outcomes separately from observations on the phone.

Activity history regression: run `flutter test --no-pub test/saved_activity_test.dart test/profile_combined_activity_test.dart test/profile_tool_call_test.dart test/profile_subagents_test.dart`. Check restored Tasks/Agents, exact child-index input joins, empty task snapshots, background dispatch, roster discovery on reopen, exception-only tool headers and delivered timing. Inspect saved rows at 360 dp in both themes and 200% text; saved agents never offer steering or interruption.

The stock activity catalog in `test/tool_activity_catalog_test.dart` exercises
all source-shaped variants in `test/fixtures/stock_activity_shapes.json` through
the actual shared renderer. Capture with `CAPTURE_ACTIVITY_CATALOG=true` and the
same real font directory; inspect `build/activity-catalog/` with the family
images. The [field policy](design/activity-field-policy.md) owns each tool's
selection and action scope; fixtures do not claim live executions.
