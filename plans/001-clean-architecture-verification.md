# Verification and prevention contracts for Wing's architecture program

Companion to `001-clean-architecture-program.md`, planned at Wing `a5650fa675209b6a782a5adf3f39ff12c53efb4c`, 3 October 2026. These are **future execution gates**, not claims that new guards/tests already exist. Working directory for commands: `/home/dev/projects/hermes-android/hermes-android`. In this workspace initialize the existing toolchain with `source ../.toolchain/env.sh`; on another host use the documented contributor setup. Keep Flutter/build/Gradle operations sequential and retain existing user work.

## Commands and what they establish

Run focused tests during a change, the complete host checks when accepting a coherent batch, and affected build/native/renderer checks at the corresponding boundary. At program closure run all required checks against one fixed source/diff. Repeat only when changes/failures/new concerns warrant it.

| Gate | Exact command | Required outcome |
| --- | --- | --- |
| Dependency graph after declaration changes | `flutter pub get` | Resolves on the pinned toolchain; reviewed manifest/lockfile changes only |
| Static analysis | `flutter analyze --no-pub --fatal-infos` | Exit 0; no issues |
| Host behavior | `flutter test --no-pub --reporter expanded` | Exit 0; every new regression passes; named opt-in skips recorded |
| Release tooling | `python3 -m unittest discover -s scripts/tests -v` | Exit 0 |
| Offline QA tooling | `python3 -m unittest discover -s tools/qa -p 'test_*.py' -v` | Exit 0; PR/relevant release CI enforce this command |
| Release metadata | `python3 scripts/release.py check` | Exit 0, consistent metadata |
| Android compilation | `flutter build apk --debug --no-pub` | Exit 0; normal development entry point compiles |
| Native JVM boundaries | `./android/gradlew -p android :app:testDebugUnitTest --rerun --no-daemon` | Fresh task execution; 0 failures/errors; passing XML evidence |
| Whitespace | `git diff --check` | Exit 0 |
| Rule contract fixtures (proposed) | `flutter test --no-pub test/architecture_contract_test.dart` | Every rule rejects its bad fixtures and accepts its valid fixtures |
| Complete architecture lint run (proposed) | `dart run tools/architecture/check_all.dart` | Exit 0; no new violations in migration, zero violations/baseline entries at closure |

Every individual linter must also have a direct command, for example `dart run tools/architecture/rules/no_domain_ui_dependency.dart`. Choose the simplest accurate implementation language; the exact command belongs beside its rule specification. Do not force a Dart symbol resolver onto checks of XML, JSON or workflow structure. New checks must run on clean CI without ignored local helper files.

The existing PR workflow already performs analysis, host tests, a debug APK build, native JVM tests, release instrumentation guards and renderer isolation. Retain its error aggregation/exit behavior. Add missing/new checks to the final outcome rather than creating steps whose failure is accidentally ignored. Demonstrate failure propagation with an isolated synthetic bad fixture; do not leave intentional failures in production or depend on an actual pushed broken branch.

For affected renderer/assets behavior, existing commands are:

```sh
npm ci --prefix scripts/diagram-preview --ignore-scripts --no-audit --no-fund
node scripts/diagram-preview/node_modules/playwright-core/cli.js install chromium
npm test --prefix scripts/diagram-preview
```

Use the existing pinned Node/Playwright setup from `.github/actions/test-diagram-preview/action.yml`; system prerequisites may require its documented `--with-deps` installation. This verifies the actual Chromium renderer and response policy, not Android WebView acceptance. Compile supported alternate entry points when their caller/configuration graph changes. After native integration mode changes, use the documented normal pub step for a release build rather than retaining the test-only plugin registrant. Signing/publication is outside this plan.

## Small individual linters: acceptance contract

For **every discovered incorrect pattern**, the executor invokes `tools/agent_skills/create-regression-guards/SKILL.md` and records the feasibility decision. Use the user's preferred architecture: many small deterministic independent linters, each with one purpose, a small fixture suite and its own command. A runner invokes them; it does not become a giant policy implementation. Standard Flutter/Dart/Android lints count when they actually detect the property and CI enforces them.

Each rule specifies: stable ID; violated invariant and concrete consequence; authored scope; diagnostic with path/line and remedy; valid exceptions; independent command; bad/valid fixtures; runtime evidence; migration-baseline disposition. Phase 0 measures cold startup and the median of three warm runs on the actual checkout, records host/SDK/input size, and sets justified numeric budgets for individual and aggregate local feedback before further rules roll out. Subsequent acceptance benchmarks use the same conditions and must fit those budgets; share immutable parsed analysis where that removes repeated work. Record and investigate regressions rather than silently increasing budgets. CI timing is informational so scheduler noise cannot change a correctness verdict. Output order/exit status must be deterministic; no network, model call or wall-clock policy decision. Local incremental runs include affected dependencies/callers; full CI is authoritative for cross-file rules.

Separate tooling startup from actual rule cost. If loading the SDK/analyzer dominates, benchmark a compiled rule/runner entry point or invoke independent rules in one process over shared immutable parsed input. The runner may amortize startup while each rule retains its own interface, command and fixtures. Source/configuration/SDK-aware caches belong in ignored tooling output, never tracked binaries or stale analysis. A six-second startup multiplied across many tiny rules would defeat fast local feedback even if each rule's internal traversal were cheap.

Choose representation by the property. Parsed imports suffice for dependency edges; resolved receiver symbols are needed for mutation/transport access and aliases. Handle package/relative/conditional imports, exports and `part` libraries. Test prefix/alias/cascade/extension/tear-off cases that matter to the rule. A regex search is an inventory aid; it must not pretend to understand arbitrary Dart business logic. Formatting-independent structural checks should accept equivalent valid code.

Test a guard through its actual entry point: bad code produces the intended rule diagnostic and nonzero status; valid code produces no diagnostic; unrelated failures cannot satisfy the negative test. Keep sample invalid programs outside ordinary production analysis/test discovery. Verify stale baseline entries also fail so an exemption cannot quietly outlive a migration. Prefer private ownership and immutable public types where the compiler can prevent a misuse directly.

### Initial rule backlog

Names are proposed; phase 0 implements individual rules with these responsibilities.

| Rule/property | Suitable check | Important valid case |
| --- | --- | --- |
| Domain imports belong to domain | Small parsed/resolved graph linter for models → UI/controller/I/O | Pure Unicode/value helpers; no blanket ban based on a Flutter package name |
| Business owners do not depend on views | Individual graph linter for repository/coordinator → screen/widget/rendering | `foundation` notifications; narrowly classified lifecycle/platform glue |
| Controllers contain no rendering machinery | AST/type rule for `BuildContext`, dialogs/routes, text/scroll/animation controllers in business owners | The separate presentation/view owns those resources |
| Views access typed feature interfaces | Resolved-symbol rule rejecting HTTP/RPC/storage/channel adapters in view roles | Composition constructs adapters; a view calls its feature command |
| Business state has one writer | Private fields/read-only snapshots plus a narrow resolved-assignment rule if needed | UI-owned cursor, scroll and expansion; owner-internal mutation |
| Authored dependencies are acyclic | Individual library-graph cycle check, collapsing actual `part` ownership | Framework/generated libraries outside authored graph |
| Every authored library has a role | Inventory/manifest linter; reject unclassified additions and stale entries | Explicit narrow composition/platform roles |
| Root/deletion inventory is complete | Individual root/reference/candidate checks; no unexplained orphan or stale root | Real native callback/string registration and supported opt-in tools |
| Direct packages/assets have an owner | Manifest/import/loader/resource checks plus explicit dynamic-root evidence | Transitive package use, fonts, build/generator and licensing inputs |
| Fixture capabilities match inspected stock | Small contract fixture/schema check tied to inspected stock revision | Deliberate disconnect injection without fictitious production support |
| QA/guard failures affect CI outcome | Workflow/runner contract test using a failing synthetic child process | Existing workflow summary/error aggregation |

An ownership role manifest cannot legitimize business logic by classifying an entire widget file as composition. Review every such classification. Static gates complement the exhaustive view review; they cannot prove every business rule has left UI.

## Regression and prevention matrix

The review IDs below identify concrete issues; the description is sufficient to build the test without the previous conversation. Existing tests are patterns/entry points, not proof the new case already exists.

| Item | Required observable scenario | Extend existing tests | Prevention decision |
| --- | --- | --- | --- |
| D01 stale resume | Hold idle resume; deliver newer start/delta/pending input/terminal; release old response. Preserve latest facts through open, reconnect and queue recovery, including scope/runtime replacement | `profile_workspace_controller_test.dart`, `profile_outgoing_draft_recovery_test.dart` | Encapsulated runtime writer + structural ownership lint; deterministic event-order regressions prove freshness, which general static lint cannot |
| D02 draft rollback | Fail persistence while newer text/files are edited. Preserve new work; clean only abandoned staging. Also cover failure with no intervening edit | `profile_shared_draft_test.dart`, `composer_draft_store_test.dart` | Single composer writer; revision/cleanup regression. Do not impose a universal ban on catch-block rollback |
| D03 slash completion | Actual selection; recreate store/controller; exact completed text/suffix/Unicode cursor survives. Save failure preserves work | `slash_commands_test.dart`, `profile_draft_recovery_test.dart` | Direct business-field assignment guard/private interface |
| D04 acknowledged deletion | DELETE confirmed; local cleanup fails. All list/chat projections keep tombstone; cleanup retry sends no second DELETE | `chat_browser_mutations_test.dart`, `chat_browser_actions_test.dart` | Owner command/interface guard + failure-injection regression; lint cannot infer server acknowledgement semantics |
| D05 task baseline | Actual task route opens A, refresh sees B, edit only name: send name only. Same-field conflict retains draft; untouched schedule/model/destinations remain current | `scheduled_tasks_screens_test.dart`, `scheduled_tasks_controller_test.dart` | UI transport/mutation guard; immutable edit-session baseline; route refresh regression |
| D06 task owner | Moved task/duplicate ID/missing membership/failed preflight prevent wrong scoped dispatch; matching-owner succeeds; contradictory response remains uncertain | `scheduled_tasks_repository_test.dart`, `scheduled_tasks_transport_test.dart` | Typed task/scope and one mutation interface; contract regressions; document non-atomic stock limitation |
| D07/A02 state dimensions | Completed/running/failed/interrupted crossed with representative approval/clarification/secure input, disconnected waiting and child work. Clearing last input after completion cannot set running; browser/Recents/monitoring agree | `profile_combined_activity_test.dart`, `profile_activity_status_test.dart`, `background_monitoring_activity_test.dart`, `workspace_retention_test.dart` | Canonical domain projection/no model→controller guard; transition/property tests, not a ban on enum names |
| D08 snapshot semantics | Roundtrip hidden rows, notices, steering/delegation details. Offline render preserves meaning; restored snapshots cannot enable runtime decisions | `workspace_reading_snapshot_test.dart`, `workspace_snapshot_limits_test.dart` | Typed snapshot projection; schema/roundtrip tests; parsing stays outside views |
| A01 inactive chat paths | Shipping auth/handshake/RPC correlation/events/close/outbox/history still work after removal; exclusive old tests disappear | `gateway_headers_transport_test.dart`, `conversation_outbox_lifecycle_test.dart`, `profile_live_contract_test.dart` | Member/root reachability checks and documented supported entry points |
| A03 ownership inversions | Model/intelligence parsing, retained diagnostics, generation/disposal/callbacks and captured-profile behavior survive moves | `profile_intelligence_test.dart`, `administration_health_session_test.dart`, `profile_diagnostics_panel_test.dart` | Domain/business-owner import linters |
| N01 image work | Bound dimensions/frames/allocation before decode; ordinary large JPEG/PNG/WebP, orientation and metadata stripping; cancellation/stale failure leaves no orphan or wrong draft | `attachment_draft_service_test.dart`, `profile_attachment_parity_test.dart` | Narrow worker/UI dependency or call-placement guard where accurate; allocation/cancellation/worker regressions; phone profile acceptance |
| N02 blocked intake | Provider stalls open/read; deadline/no late commit/cleanup hold; subsequent queue/share/discard/camera/output operations proceed | Existing native policy tests; extend `tools/qa/check_external_share.py` with a disposable stalled provider | Native thread/resource architecture check if resolvable; actual blocking-provider acceptance is essential |
| N03 voice transfers | Actual file reads/writes leave main thread; stop/Home/destruction/storage failure/oversize/successive playback reject stale results and clean resources | Voice host suites; extend native thread/lifecycle tests and `scripts/test_native_voice.py` | Existing Android thread lint/annotations where effective; runtime thread assertions and actual native journey |
| P01 fence scan | Exact grammar/content for dense/mixed/unfinished/CRLF/indented fences; bounded work/allocation growth | `markdown_fence_scanner_test.dart`, `markdown_segment_correctness_test.dart`, `markdown_parse_worker_test.dart` | A narrow AST guard for search-over-copied-tail in this scanner only if accurate; algorithmic/grammar regressions otherwise |
| P02 browser groups | Populated/empty projects across profiles/Home/filters produce identical groups; membership work scales with P+S | `profile_workspace_browser_test.dart`, browser data suites | Move pure projection out of widget; measured operation-count regression. Avoid globally banning nested loops |
| P03 transcript investigation | Count unchanged structure work for short/long loaded history and live tail. Any optimization preserves keys/anchors/selection/grouping/pagination | `streaming_work_budget_test.dart`, `markdown_render_reuse_test.dart`, streaming scroll suites | Existing deterministic work/identity budgets; profile before/after. Evidence-backed no-change is valid if cost not material |
| V01 offline QA CI | Existing offline QA suite runs; synthetic failing test causes nonzero CI outcome | `scripts/tests`, `tools/qa` test modules and workflow outcome checks | Small CI-required-gate rule/runner contract |
| V02 fixture experiment | Stock-shaped active client probes/disconnects still work; removed fake recovery methods are not advertised or dispatched | `tools/fake_gateway/test_fake_gateway.py` against separately running loopback fixture, per fixture README | Fixture capability/schema lint with pinned upstream evidence; independent fixture behavioral checks |

Regressions belong at the owner/interface that fails. Most business tests should not need a widget. Keep widget tests for actual edits, dialogs, routing, keyboard, dirty guards, error rendering and dependency wiring. Use held futures/injected stores/clocks/gateways rather than nondeterministic sleeps. Test exact data-loss/ordering cases, not every internal method. Standard [Flutter testing guidance](https://docs.flutter.dev/testing/overview) distinguishes unit, widget and integration evidence; the existing project testing guide defines the concrete acceptance scope.

For every migrated feature also exercise load failure/retry, duplicate submit, readback mismatch, request finishing after navigation/scope change/disposal, local save failure where relevant, and correctly owned cleanup. Confirmation tests must verify the decision applies to the originally captured request, not a newly selected target.

## Native, UI and current-stock acceptance

Read each driver before running it; use disposable emulator/app data and owned fixtures. These commands have side effects on the development package/fixture. They are available procedures, not blanket live-server permission.

```sh
python3 scripts/test_native_file_transfer.py --device <emulator-id> --output build/native-file-transfer-review
python3 scripts/test_native_voice.py --device <emulator-id> --output build/native-voice-review
python3 tools/qa/check_activity_reentry.py --serial <device-id> --package com.tarkilhk.wing.dev
flutter test --no-pub integration_test/profile_expansion_scroll_test.dart -d <emulator-id> --no-uninstall
```

External-share acceptance uses a different package, `com.tarkilhk.wing.notificationqa`. Prepare the notification fixture first, on a fresh disposable **x64** emulator with empty native intake (adapt target ABI to a different emulator):

```sh
ORG_GRADLE_PROJECT_notificationQa=true flutter build apk --debug --target-platform android-x64 -t integration_test/notification_revamp_device.dart
adb -s <emulator-id> install --no-incremental -r -g build/app/outputs/flutter-apk/app-debug.apk
adb -s <emulator-id> shell am start -n com.tarkilhk.wing.notificationqa/com.tarkilhk.wing.MainActivity
python3 tools/qa/check_external_share.py --serial <emulator-id>
```

Verify the fixture renders and intake is empty before invoking the driver. This build/install/launch sequence is separate from ordinary development-package file-transfer/voice checks. See `docs/TESTING.md` under Notification checks for the complete fixture journey and cleanup. Never install the fixture under a personal/production package.

N02 requires the new stalled-provider scenario; the existing URI origin/grant helper alone does not prove starvation recovery. N03 requires actual thread/lifecycle evidence; ordinary JVM policy tests do not emulate recorder/player/Looper behavior. Run affected notification/background and administration/task journeys from `docs/TESTING.md`. Inspect real rendered narrow-phone and enlarged-text light/dark states for changed UI, including loading/errors, dialogs, dirty guards, keyboard/reachability, semantic labels, focus and reduced motion. Preserve Studio's documented control exceptions rather than substituting arbitrary defaults.

Before contracts change, fetch latest upstream main, inspect actual touched routes/methods, and pin the inspected SHA in evidence. Use stock-shaped adapter fixtures for deterministic failures, then authorized current-stock live acceptance for touched APIs. Mocks cannot establish absent backend concurrency guarantees. Do not automatically retry acknowledgement-uncertain writes or invoke a model to simulate a contract check.

For measured performance use opt-in instrumentation and the existing replay entry points, then matched physical-phone profile-mode workloads. [Flutter's profiling guidance](https://docs.flutter.dev/perf/ui-performance) supports profile-mode physical-device evidence. Follow the repository's stricter workload/privacy/archive contracts: typing 200 edits; streamed replay with exact text/control delivery; navigation/retention soak; native file/image work. Require zero unchanged transcript builds and zero workspace-monitoring notifications for draft-only edits, zero saved-Markdown rebuilds during streamed chunks, bounded resource ownership after settlement and no missing terminal/approval events. Set any new numeric phone-performance threshold from recorded baseline and the target device before using it as a gate; do not claim host timing is phone latency.

## Evidence, review and stop conditions

Each accepted batch records: source SHA/diff, owner/invariant, regression red/green evidence, individual prevention rule/command/fixtures/runtime, focused and broader outcomes, deleted closure and root proof, remaining acceptance prerequisite. A lower test count from deleting obsolete implementation tests is valid when active behavior coverage is accounted for. Never preserve a test count by duplicating assertions around removed code.

Static guards must be reviewed for false positives and loopholes. Domain/ownership correctness also needs a fresh human/agent review of the actual implementation and three change-locality examples. A green guard is evidence of its exact property, not of all business correctness.

Pause dependent work for a missing product/data/compatibility decision or unavailable stock capability. Continue unaffected work when a device/credential prerequisite is missing, but leave the corresponding acceptance item pending. Failed gates, unresolved mutation bypasses, unresolved deletion candidates, stale migration exemptions, unverified native boundaries and material review findings prevent completion. Publishing, deployment and signed-store release remain separate actions.
