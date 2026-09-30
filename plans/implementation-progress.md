# Release-readiness fixes

User authorized implementation of all review findings on 30 September 2026.
Original review: [release-readiness-review-2026-09-30.md](release-readiness-review-2026-09-30.md).
Baseline app commit: `151ee281c6009024449c836b18ed8910c4ce3e10`.
Initial stock Hermes API reference: `8d30c4eaabd85edb77a02fef6c5388d9344ef80c`, 30 September 2026 02:10:10 UTC.
Current official upstream main verified again for emulator/live work:
`f42f579cf8bac4918ac9599bece71618afadd846`.
The authenticated deployed server remains clean stock
`02e41181107b11214e7852321e7ec890a99f3ca6`; it was not upgraded.

Source changes are authorized. Implement current stock behavior directly; backend
changes and compatibility shims are out of scope. Preserve existing user edits.
Agents own disjoint file groups; parent schedules Flutter/Gradle verification
sequentially and reviews each diff. No commit, push, deployment or personal-device
installation is part of this task.

All 26 findings are implemented and passed the applicable host checks below.
Fresh agents reviewed security, persistence, file lifecycles, retention, UI
fixtures and the final evidence record. Emulator-first follow-up adds the native
and real-backend evidence below.
Physical-phone energy and quality checks remain outstanding.

| Finding | Status | Implementation / verification |
| --- | --- | --- |
| R01 Console redirect credentials | Verified | Shared no-redirect connector; 18 transport tests passed |
| R02 Atomic connection import | Verified | Durable serialized transaction and cold rollback; backup/storage batch: 81 passed |
| R03 Explicit project cwd | Verified | Explicit cwd provenance and server acknowledgment; controller regressions and full suite passed |
| R04 Notification handoff authenticity | Verified | Purpose-bound one-use notification handles; final Android debug build and native JVM tests passed |
| R05 Share URI origin | Verified | External provider/read-grant validation before metadata/open; native JVM policy passed |
| R06 Malformed notification input | Verified | Bounded native notification parsing; 9 native JVM tests passed across security/policy |
| R07 Preference schema | Verified | Typed setting schema with explicit skipped count; backup batch passed |
| R08 Uncertain destructive acknowledgments | Verified | Verified refusal allowlist; uncertain storage/transport failures reconcile; controller regressions and full suite passed |
| R09 Server-local usage dates | Verified | Preserved server date keys and truthful chart padding; analytics tests passed; normal/enlarged renders inspected in both themes |
| R10 Script-only scheduled runs | Verified | Source-aware script output previews; mixed-history screen tests and full suite passed |
| R11 Bounded backup input | Verified | 2 MiB streamed/codec limit plus structure bounds; backup batch passed |
| R12 File deadlines/cancellation | Verified | Aborted HTTP deadlines and tracked screen-owned reads; 17 file/disposal regressions passed |
| R13 MCP dirty navigation | Verified | Dirty-editor Back/profile switch guards; UI checks and full suite passed |
| R14 Pending mutation dialogs | Verified | Pending dialogs freeze input and dismissal; UI checks and full suite passed |
| R15 PR Android compilation | Verified | PR debug compilation and native JVM gate; final local APK and JVM checks passed |
| R16 Renderer isolation CI | Verified | Pinned Chromium browser isolation gate on PR/release; real browser harness passed |
| R17 Reliable visual fixtures | Verified | True view metrics, notified server history and usage fixtures; normal/enlarged renders inspected in both themes |
| R18 Project membership index | Verified | Shared adequate membership tree with explicit Home proof and invalidation; controller regressions and full suite passed |
| R19 Bounded idle owners/chats | Verified | 20 settled transcript bound and configured/mounted/work owner leases; synthetic soak, route and full-suite tests passed |
| R20 Browser notifier cleanup | Verified | Listener-aware retired row notifier cleanup; browser tests and full suite passed |
| R21 Disconnected modules | Verified | Removed 31 obsolete production modules and their dedicated tests; live test helper relocated and active URL helper extracted; all 241 app files reachable from 47 application, integration and performance entry points |
| R22 Touch targets | Verified | 48 dp clear/edit hit areas; UI tests and full suite passed |
| R23 Keyboard composer actions | Verified | Keyboard focus/menu navigation and escape; composer tests and full suite passed |
| R24 Calendar-date grouping | Verified | Calendar ordinal date grouping; standard and New York DST tests passed |
| R25 Large-text setup label | Verified | External Custom address label at enlarged text; normal/enlarged renders inspected in both themes |
| R26 Portable visibility preferences | Verified | Logical connection visibility namespace survives cloud reauthentication; backup batch passed |

## Final verification

Run Flutter and Gradle checks sequentially, with the workspace toolchain environment
loaded from `../.toolchain/env.sh`.

| Check | Result | Reproduce |
| --- | --- | --- |
| Static analysis | Final run: no issues | `flutter analyze --no-pub --fatal-infos` |
| Complete Flutter suite | 2,592 passed, 15 opt-in live tests skipped; no failures (4:21), including final stop/read/runtime and schema regressions | `flutter test --no-pub --reporter expanded` |
| Final ordinary Android debug APK | Built in 15.5 seconds and installed on the disposable emulator; no release credentials | `flutter build apk --debug --no-pub` |
| Local release APK packaging | Built in 72.8 seconds (73.4 MB); SDK 36 `apksigner verify` passed (exit 0) using existing signing settings; not installed or published | `flutter build apk --release`; `/tmp/wing-emulator-final-release-build.log` |
| Native Android JVM behavior | 9 passed; no failures, errors or skips | `./android/gradlew -p android :app:testDebugUnitTest --no-daemon` |
| Real Chromium renderer isolation | Passed; opaque HTML sandbox, blocked parent/storage/HTTP access, SVG/Mermaid behavior, complete 2/8/32 MiB documents and both Studio themes | With Node 22.23.3: `npm ci --prefix scripts/diagram-preview --ignore-scripts --no-audit --no-fund`, `node scripts/diagram-preview/node_modules/playwright-core/cli.js install --with-deps chromium`, then `npm test --prefix scripts/diagram-preview` |
| Release tooling | 28 passed | `python3 -m unittest discover -s scripts/tests -v` |
| Calendar/DST regressions | 3 passed with New York timezone | `TZ=America/New_York flutter test --no-pub test/chat_date_grouping_test.dart` |
| Workflow syntax and patch whitespace | Passed | `actionlint .github/workflows/pr-quality.yml .github/workflows/release.yml` and `git diff --check` |

The latest complete-suite log is
`/tmp/wing-emulator-final-complete-host-suite.log` (2,592 passed / 15 skipped).
The final analyzer log is `/tmp/wing-emulator-final-complete-analyze.log`.
Other host gate logs are `/tmp/wing-fixes-final-analyze.log` (earlier gate),
`/tmp/wing-fixes-full-suite-complete.log` (the earlier 2,581-test gate),
`/tmp/wing-fixes-final-debug-build.log`, `/tmp/wing-fixes-native-jvm.log`,
`/tmp/wing-fixes-renderer-final.log`, `/tmp/wing-fixes-release-tool-tests.log`
and `/tmp/wing-fixes-dst-tests.log`. Earlier partial or failed runs are diagnostic
records, not acceptance evidence.

Rendered captures under ignored `build/studio-review`, `build/connection-review`,
`build/usage-review` and `build/scheduled-tasks-review` were inspected at normal
and enlarged text sizes in both themes. They cover populated content, long
labels, loading/errors, pending mutations and reachable controls.

Independent reviews also closed screen-owned file-read cancellation, notification
delivery owner leases, cross-widget-lifecycle identity caching and cloud
reauthentication visibility gaps. Synthetic retention checks observe bounded
chat contents, owner counts, socket closes and reconnects; they do not establish
physical-device heap, frame latency or battery improvement.

## Emulator and real-backend follow-up

The user authorized emulator-first acceptance, deferring their phone. Runs use
API 36 / Android 16 x86_64 AVD `hermes_api36`, `emulator-5556`, with an ephemeral
read-only disk and development/notification-QA package IDs. Fixture credentials,
messages and files are synthetic; authenticated live checks use a temporary
private runtime credential file. The connected SHIELD TV was not targeted.

| Check | Confirmed result | Evidence / reproduction |
| --- | --- | --- |
| Ordinary app startup and reentry | 4 startup checkpoints passed after denying both native permissions; restart does not reprompt, welcome/setup usable and inspected. All 3 launcher actions resolve; cold launch, 3 competing-task cycles and notification-style reentry retain the same activity/task, one Recents card and rendered content | `/tmp/wing-emulator-final-startup.log`, `/tmp/wing-emulator-final-launcher.log`, `/tmp/wing-emulator-final-reentry.log`; `build/emulator-acceptance/startup/acceptance.json` |
| Connection journey | 2 native tests passed in both themes | `integration_test/connection_journey_native_test.dart`; `/tmp/wing-emulator-connection-journey.log` |
| Queue editing | 7 native tests passed, including actual IME opening, cancellation, steering and large text/attachment | `integration_test/queued_message_edit_test.dart`; `/tmp/wing-emulator-queued-edit.log` |
| External share boundary | 5 foreign-UID cases passed; invalid origins/grants rejected before provider access, granted bytes imported exactly | `tools/qa/check_external_share.py`; `build/emulator-acceptance/external-share/acceptance.json` |
| Notification handoff and reading | All 8 native flow checkpoints passed: forged/raw/wrong-type inputs, exact FIFO decisions, failure retention, Always confirmation, privacy, remote reconciliation and reply reading; both themes at 100%/200% inspected | `tools/qa/check_notification_revamp.py`; `/tmp/wing-emulator-notification-fixed-check.log` |
| Notification persistence and counts | 5 restore/read/dismiss checkpoints and 4 count/privacy checkpoints passed | `scripts/test_native_notification_restore.py`; `/tmp/wing-emulator-notification-restore-selector.log`, `/tmp/wing-emulator-notification-counts.log` |
| Unopened cached-chat notification | 2 native checkpoints passed: first fresh notification includes all 3 questions, real text/options and Review without opening the chat; monitoring stops afterward | `integration_test/notification_cold_input_device.dart`, `scripts/test_native_cold_notification.py`; `/tmp/wing-emulator-cold-input-check.log` |
| Background monitoring | One poll timer/one tick during 35 seconds of work; zero timers/new ticks after settling; wake-lock/service/engine release and Doze delivery passed with battery exemption | `tools/qa/check_background_monitoring.py`; `/tmp/wing-emulator-background-check.log`; CPU/PSS diagnostics in `build/emulator-acceptance/performance/` |
| Configuration backup | 2 Flutter tests and 5 native picker/share steps passed; real Keystore, plain Merge, encrypted Replace, wrong passphrase and owned cache/helper cleanup verified | `scripts/test_native_config_backup.py`; `build/emulator-acceptance/config-backup/acceptance.json` |
| Native file transfer | 7 Flutter tests and 6 native picker/share steps passed; owned files/cache cleaned | `scripts/test_native_file_transfer.py`; `build/emulator-acceptance/file-transfer/acceptance.json` |
| Local voice | 2 Flutter tests passed with real permission denial/grant, Home cancellation, AAC capture/decode/playback and 5 offline TTS samples; 9 voices available | `scripts/test_native_voice.py`; `build/emulator-acceptance/voice/acceptance.json` |
| Android WebView | Complete 32 MiB HTML, real control click and parent/storage sandbox passed; same-emulator complete HTTP 200 control, rejected fetch/image, enforced connect-src/img-src violations and zero sandbox probe hits passed; capture inspected | `scripts/check-large-html-native.mjs`; `/tmp/wing-emulator-webview-http-check.log`; `build/large-html-review/native-http-isolation.json` |
| Transcript and streaming interaction | 28 native tests passed; 15 captures saved, with representative follow/reading modes inspected in both themes at 100%/200% | `integration_test/profile_expansion_scroll_test.dart`; `/tmp/wing-emulator-transcript-scroll.log`; `build/emulator-acceptance/transcript-scroll/` |
| Native editors and plugins | 4 administration, 1 scheduled-task, 4 slash-completion and 2 dependency-plugin tests passed | `/tmp/wing-emulator-administration.log`, `/tmp/wing-emulator-scheduled-tasks.log`, `/tmp/wing-emulator-slash-completion.log`, `/tmp/wing-emulator-dependency-plugins.log`; `build/emulator-acceptance/native-editor-checks.json` |
| Broad native product journeys | 8 tests per theme passed (16 total); all 40 PNGs preserved. Large-text settings, draft/model, usage/health, input/approval/queue, Identity, drawer/version, vault and fork cases inspected in both themes with no concrete visual defects | `integration_test/roadmap_emulator_test.dart`; `/tmp/wing-emulator-roadmap-dark-complete.log`, `/tmp/wing-emulator-roadmap-light-captures.log`; `build/emulator-acceptance/roadmap/{light,dark}/` |
| Existing Hermes read-only host integration | 3 passed: normal password authentication, discovery of 7 profiles, scoped catalogs and real ticketed WebSocket ready/ping/capabilities | `test/existing_backend_readonly_live_test.dart`; see runtime credential-file instructions in [Testing](../docs/TESTING.md) |
| Existing Hermes native UI | 1 passed: actual password sign-in, default-profile Administration/models/Identity and deployed version 0.21.5; Health drawer entry reachable without running health operations or opening chats; private emulator credential removed and verified | `integration_test/administration_existing_server_live_test.dart`; `/tmp/wing-emulator-existing-backend-administration-final.log` |

The final ordinary debug APK is retained at
`build/emulator-acceptance/ordinary-debug.apk`, SHA-256
`56257b7cf0629de00b7bd02ff7d085a4357a695ef4045306985828d2fa59a32b`
(`/tmp/wing-emulator-final-ordinary-build.log`). A literal check of 853 source
files and the uncompressed APK found no copy of the supplied dashboard password;
no secret values were logged. The local release APK is
`build/app/outputs/flutter-apk/app-release.apk`, SHA-256
`f5970b43ff72f60ed25d4b4348dcb0051707a62446fe106303deaf71628a0d67`.
A second raw ZIP-entry scan found no supplied password in either ordinary APK.

Cleanup is verified: host/private-emulator credential files and the one-off
startup driver are removed; helper package absent; owned ADB forwards/reverses
cleared. The disposable AVD stopped and its process exited. Only the untouched
SHIELD remains connected. Captures and acceptance artifacts are retained under
ignored `build/`. Final patch whitespace, Node 22 syntax, 40-capture counts and
native HTTP proof checks passed.

Emulator acceptance uncovered a real notification bug: `inactive` → `resumed`
could leave an already-visible answer without another read check. The lifecycle
refresh fixes it; the new regression first failed, then the 9-test host read batch
and complete native notification sequence passed. Temporary debug tags were removed.

Current-stock review also removed registry-wide `process.stop` from chat-local
stop: stopping one chat cannot kill unrelated backend processes. Eight focused
stop regressions cover scope, discarded process-list reads and
owner/runtime changes after awaits. Chat-local stop requires a current read and
rejects stale ownership before claiming success. The final targeted
controller/contract batch passed 154 tests with one opt-in live test skipped
(`/tmp/wing-emulator-current-stock-final-regressions.log`). Two strict-current-schema
tests cover the
latest stock response shape. Fields suspected from the older `d177` reference
were supported by current upstream and retained; no compatibility fallback was added.

The first native file-transfer run stalled during VM startup. A diagnostic rerun
passed without adding a fake delay or pump workaround. Failed selector/startup
runs remain diagnostic records and are not acceptance results.

The broad native product fixture uses populated daily/year usage with an exact
6,380-token / 1.25-paid-cost total and unknown/partial annotations. Doctor/Audit
responses follow stock shapes; intentional incomplete profile checks retain
redaction/retry assertions. The recovered light run passed all 8 tests again;
only the final complete logs and 40 preserved captures support visual acceptance.
These injected-gateway journeys do not establish live model or health execution.

The initial ad-hoc release build used `--no-pub` after native integration and
failed with an integration-only generated registrant reference. Diagnosis
confirmed the SDK skips mode-specific regeneration with that flag; existing
release script/workflow already use the supported normal pub step. That failed
attempt is diagnostic (`/tmp/wing-emulator-release-no-pub-diagnostic.log`), not a
production-source defect or accepted release gate.

One optional model probe is prepared behind `RUN_MODEL=true`; approval and
execution are pending. It owns one disposable QA chat on the default profile,
sends one prompt, and permits cleanup only after that chat is idle. Read-only
integration does not establish model streaming or tool execution.

## Observed dependency maintenance

The successful release build reports `flutter_markdown` as discontinued and
names `flutter_markdown_plus` as its replacement. It also warns about future
Kotlin Gradle Plugin migration for `shared_preferences_android` and
`url_launcher_android`, and 37 newer dependency versions outside current
constraints. These are maintenance signals, not failures of the pinned current
build. No blanket upgrade was performed. The prior OSV check of 109 resolved
packages reported no findings; that does not certify all future releases.

## Deliberate format changes

Configuration imports accept `wing-config` version 2 only. Visibility settings
use logical saved connection IDs; the old identity-based namespace is not read
or migrated and defaults apply to those old filters. Plaintext credential
metadata is rejected. See [Configuration backups](../docs/CONFIGURATION_BACKUPS.md)
for supported settings, bounds and restore behavior.

## Acceptance limits

Native acceptance above establishes behavior on one disposable API 36 emulator,
including actual intents, URI grants, Android permissions, IME opening and WebView.
The debug CPU/PSS samples are diagnostics, not energy or release performance
benchmarks. The Doze fixture is battery-exempt; it does not establish delivery
under restricted OEM/network policies. Native HTML HTTP isolation is now
verified on this emulator; other WebView/device versions remain separate. TTS
start callbacks
of 71–344 ms do not establish audible latency, intelligibility or transcription
quality.

Physical-phone energy, thermals, frame/input latency, OEM lifecycle and network
restriction, microphone/speech quality and device-specific WebView/IME behavior
remain for the agreed later phone phase. Local APK signature verification does
not establish publisher signing identity, distribution readiness or store
acceptance. Authenticated read-only live checks do not establish mutating features,
model/tool execution or every deployed profile. No commit, push, server upgrade,
backend modification or personal-device installation was made.
