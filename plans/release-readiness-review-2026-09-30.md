# Wing release-readiness code review

Reviewed 30 September 2026 against app commit `151ee281c6009024449c836b18ed8910c4ce3e10`.

## Assessment

**Hold a broad public release until the three P1 findings are fixed and verified.** The app has a substantial testing baseline and thoughtful product decisions, but currently has a credential redirect leak, a failed-import path that can associate credentials with the wrong endpoint, and a project-session contract mismatch that can send agent work to the wrong directory. Passing host tests do not cover these boundaries.

There are also concrete recovery, import-validation, Android-intent, accessibility, and performance issues worth resolving before expanding beyond a controlled pilot. This review found no P0 issue. It cannot establish that every bug has been eliminated, that native Android integrations work on a physical phone, or that device performance meets a release budget.

This is a review, not an implementation. No production source, dependencies, configuration, or permanent tests were changed. This report is the only tracked addition. Recommendations implement the requested target directly: **unmodified current upstream Hermes**, with client-only changes. They do not authorize compatibility shims, backend patches, or custom endpoints.

## Scope and method

The application repository is `hermes-android/` beneath the workspace. Its tracked production code comprises 269 Dart files (about 77,578 lines) and 14 Kotlin files (about 3,360 lines), with 317 Dart test files and 46 Dart integration-test files. Three review agents covered correctness/architecture, security/native/upstream contracts, and UI/UX; the lead independently vetted cited paths, ran the verification baseline, and added focused reproductions. This was a whole-project, risk-weighted review, not a claim that every source line received equal inspection.

Reviewed areas included session/turn ownership, prompts and destructive transcript mutations, connections and credential storage, backups, notifications and background ownership, Android sharing, file/output viewers, diagram isolation, profile/project navigation, administration, analytics, schedules, rendering and editor interactions, dependencies, release tooling, CI, and relevant product/design documentation.

Excluded from the application audit: the separate prototype checkout, archived APKs/artifacts, external service infrastructure, and the bundled backend reference checkout as an authoritative API source. Current public upstream was fetched read-only and pinned to **[`ac0cfa7db94cefa90cf3e35191f38b53888b9e17`](https://github.com/NousResearch/hermes-agent/commit/ac0cfa7db94cefa90cf3e35191f38b53888b9e17)**, published 30 September 2026. Contract findings below concern that stock revision. A live gateway was not exercised.

## Verification performed

| Check | Result | What it establishes |
| --- | --- | --- |
| `flutter analyze --no-pub --fatal-infos` | Passed; no issues | Static analysis for this checkout |
| `flutter test --no-pub --reporter expanded` | **2,860 passed, 12 skipped** | Existing host suite; skipped opt-in tests are not acceptance evidence |
| Python release-tool unit tests | **28 passed** | Release-script behavior under the tested fixtures |
| `python3 scripts/release.py check` | Passed | Current release metadata consistency, not a newly compiled APK |
| Isolated correctness reproductions | **3 passed** | Failed bulk-import inconsistency and lost-ack edit/regenerate misclassification |
| Isolated backup-codec/import reproduction | **1 passed** | Accepted numeric theme preference causes the subsequent theme read to throw |
| Synthetic two-server console redirect | Custom credential header reached the redirected server | Actual runtime WebSocket redirect behavior, with synthetic credentials only |
| Actual upstream workdir resolver, isolated from source | Project path overridden without explicit flag; honored with it | Current resolver contract, not end-to-end tool execution |
| Production usage-model and date arithmetic reproductions | Confirmed dropped out-of-range local-date usage and 23-hour midnight interval | Deterministic correctness defects |
| Selected visual fixture tests | **23 passed; 38 fresh PNGs inspected** | Host-rendered appearance within the fixture limitations below |
| Hosted locked Pub dependencies queried against OSV | 109 packages; no matching advisories returned | Scoped advisory lookup, not proof of dependency safety |
| `flutter pub outdated --no-dev-dependencies` | Direct dependencies current; newer transitive versions available | No blanket dependency migration justified by this check |
| Heuristic secret-marker scan | No matching key/private-key markers in 874 scanned tracked text files | Limited pattern scan; no real credential values printed |

Flutter was 3.44.0 / Dart 3.12.0. Flutter tests required a sandbox exception for their local test socket. An initial socket-denied attempt was stopped and replaced by the successful run above; it was not an application failure.

No Android APK build, emulator/device behavior suite, live provider/gateway tests, release signing/store validation, battery profiling, or physical-device frame/memory measurements were performed. The available ADB target was a personal Android TV, which was only listed and not modified. The real diagram-browser harness was not run: this environment had Node 18 and no located compatible browser/Playwright installation; its documented newer runtime/browser prerequisites were not installed during a read-only review.

Logs and temporary reproductions are under `/tmp/wing-review-*`, `/tmp/wing-audit-*`, and `/tmp/wing-ui-*`. They are session artifacts, not committed regression tests. Fresh visual captures are in ignored `build/connection-review/`, `build/studio-review/`, `build/administration-preview/`, and `build/studio-audit/`.

## Prioritized findings

P1 means a release blocker with substantial credential or destination-integrity impact. P2 means a material correctness/security/UX/performance or verification issue. P3 means polish or maintainability work. Effort includes focused verification: S = hours, M = roughly a day, L = multiple days. Risk describes the proposed fix, not the existing defect. Confidence is high for the stated code behavior; performance magnitude remains unmeasured where called out.

| ID | Priority / finding | Category | Effort | Fix risk | Confidence | Primary evidence |
| --- | --- | --- | --- | --- | --- | --- |
| R01 | P1 Console redirects forward custom credentials | Security / reuse | S–M | Low | High | `lib/core/services/provider_console.dart:40` |
| R02 | P1 Failed bulk import mixes old endpoints and incoming credentials | Security / integrity | M | Medium | High | `lib/core/services/connection_manager.dart:406` |
| R03 | P1 Explicit project directory is overridden by stock Hermes | Correctness / contract | S–M | Low | High | `lib/core/services/profile_gateway.dart:528` |
| R04 | P2 Exported notification handoff trusts action/review inputs | Security / native | M | Medium | High | `android/app/src/main/kotlin/com/tarkilhk/wing/ChatNotifications.kt:130` |
| R05 | P2 Share intake opens caller-supplied URIs with Wing's authority | Security / native | M | Medium | High | `android/app/src/main/kotlin/com/tarkilhk/wing/MainActivity.kt:665` |
| R06 | P2 Malformed notification extra can crash the activity | Reliability / native | S | Low | High | `android/app/src/main/kotlin/com/tarkilhk/wing/ChatNotifications.kt:133` |
| R07 | P2 Imported preference types can break startup | Correctness / validation | S–M | Low | High | `lib/core/services/config_backup_service.dart:155` |
| R08 | P2 Lost destructive-mutation acknowledgements look like refusals | Correctness / recovery | S–M | Low | High | `lib/core/services/profile_workspace_controller.dart:3952` |
| R09 | P2 Usage assumes UTC although stock Hermes groups locally | Correctness / contract | M | Medium | High | `lib/core/models/usage_analytics.dart:64` |
| R10 | P2 Script-only scheduled runs open nonexistent conversations | Correctness / contract | S | Low | High | `lib/core/models/scheduled_task.dart:90` |
| R11 | P2 Backup input allocates unbounded data before rejecting it | Reliability / performance | S–M | Low | High | `lib/core/services/config_backup_io.dart:63` |
| R12 | P2 Remote-file requests can leave opening/download controls stuck | Reliability / UX | M | Medium | High | `lib/core/services/connection_manager.dart:1505` |
| R13 | P2 MCP setup silently discards unsaved input on navigation | UX / consistency | S | Low | High | `lib/core/screens/administration/admin_mcp_setup_page.dart:221` |
| R14 | P2 Mutation dialogs can dismiss or lose newer edits while pending | UX / correctness | S | Low | High | `lib/core/screens/profile_workspace_screen.dart:1200` |
| R15 | P2 PR checks do not compile native Android code | Test coverage / CI | S–M | Low | High | `.github/workflows/pr-quality.yml:51` |
| R16 | P2 Real diagram isolation tests are absent from CI | Security verification | S–M | Low | High | `scripts/test-diagram-preview.mjs:103` |
| R17 | P2 Responsive/conversation captures do not verify their claimed state | Test coverage / UX | S | Low | High | `test/studio_layout_test.dart:184` |
| R18 | P2 Project lookup serially repeats expensive server tree scans | Performance | M | Medium | High | `lib/core/services/profile_workspace_controller.dart:3012` |
| R19 | P2 Idle chats and obsolete connection owners have no retention bound | Performance / lifecycle | L | High | High | `lib/core/services/profile_workspace_registry.dart:59` |
| R20 | P3 Removed browser rows retain their notifiers and payloads | Performance / lifecycle | S | Low | High | `lib/core/services/chat_browser_data.dart:142` |
| R21 | P3 Disconnected feature subsystems remain in production source | Cleanliness / architecture | M | Low | High | `lib/core/services/gateway_turn_application_controller.dart:1` |
| R22 | P3 Some ordinary actions have undersized touch targets | Accessibility / UX | S | Low | High | `lib/core/screens/profile_workspace_browser.dart:461` |
| R23 | P3 Composer alternatives lack a keyboard entry path | Accessibility / UX | S–M | Low | High | `lib/core/widgets/composer_action_button.dart:280` |
| R24 | P3 Date grouping counts elapsed hours instead of calendar days | Correctness / UX | S | Low | High | `lib/core/models/chat_list_view.dart:215` |
| R25 | P3 Enlarged Custom setup label truncates its meaning | Accessibility / UX | S | Low | High | `lib/core/screens/connection_setup_screen.dart:1339` |
| R26 | P3 Restored visibility settings use a device-specific old namespace | Correctness / portability | M | Medium | High | `lib/core/services/config_backup_service.dart:75` |

## Evidence, remedies, and focused acceptance checks

### R01 — Apply the existing no-redirect policy to provider consoles

`ProviderConsole.dashboard` passes saved custom gateway headers to `IOWebSocketChannel.connect` at `lib/core/services/provider_console.dart:40–44`. This is reachable through `administration_repository.dart:63–71` and provider credential renewal. It does not use the no-redirect HTTP client that ordinary chat WebSockets use in `ws_client.dart:15–29,241–245`.

A controlled two-loopback-server runtime reproduction confirmed that a custom credential header is copied to a different redirect destination. A server/proxy redirect can therefore disclose configured access credentials during console connection. The statement concerns arbitrary allowed custom credential headers, not an assertion that every standard authorization header is forwarded.

Reuse a narrowly scoped authenticated WebSocket transport policy and reject redirects consistently. Test that the redirect target receives neither a connection nor a credential header, alongside successful direct console authentication. Assess rotation for real credentials if this path has already exposed them. Fix risk is low provided console ticket/token authentication stays intact; do not build another parallel security policy.

### R02 — Make connection import an all-or-nothing credential/metadata operation

`connection_manager.dart:406–410` overwrites credentials for incoming IDs, `:412–417` clears removed credentials, and only `:419` saves the new endpoint metadata. There is no bulk rollback or serialization comparable to the single-connection save path at `:686–705`.

If a later credential write fails after an earlier existing ID has been updated, old metadata remains paired with new credentials. The next client can send credentials intended for an imported endpoint to the previously configured endpoint. A replace operation can also clear credentials for still-visible old connections before metadata persistence fails. A mock credential-store failure reproduced the first inconsistency.

Stage and verify changes, snapshot all affected credentials and metadata, serialize conflicting writes, and recover or roll back the complete import when any step fails. Account for process interruption as well as exceptions. Verify failure at every write/delete/metadata boundary, overlapping saves, and reopening storage after interruption. Medium fix risk comes from coordinating secure storage with preferences, which are separate stores.

### R03 — Send explicit working-directory intent for project chats

`profile_gateway.dart:528–539` sends `cwd` without `cwd_explicit`. `_createChat` supplies the selected project's `primary_path` at `profile_workspace_controller.dart:2559–2560` and assigns the project locally at `:2571`. Expired project-draft recovery uses the same incomplete creation call at `:2896–2909`.

Current stock Hermes gives the configured profile working directory precedence over a client `cwd` unless the client explicitly marks the directory selection. This is visible in the pinned [session workdir resolver](https://github.com/NousResearch/hermes-agent/blob/ac0cfa7db94cefa90cf3e35191f38b53888b9e17/tui_gateway/session_workdir.py#L27). Executing that actual resolver in isolation confirmed both behaviors.

When profile and project paths differ, Wing can label a chat with the selected project while agent tools operate in the profile directory. Send explicit provenance for intentional project selections, including draft recovery, and verify the acknowledged destination before presenting project ownership. Ordinary profile-default chats should continue to express inherited profile intent. Test differing directories, project recovery, and an unavailable project path. This requires no backend changes.

### R04 — Authenticate notification handoffs and derive review policy from trusted state

MainActivity is exported (`AndroidManifest.xml:38`) and forwards arbitrary notification-interaction extras at `MainActivity.kt:299,327`. `ChatNotifications.kt:130–133` parses and delivers them without authenticating the sender/action. The private notification activity being unexported does not secure this separate public entry point.

`lib/main.dart:513–514` trusts the delivered `review` flag for a resident chat, then `:557` can submit the supplied approval choice directly. Existing checks do enforce connection ownership, allowed choices, the live request ID, and mandatory review for Always. **This is not a blind arbitrary-approval bypass.** An external app that obtains a still-valid live notification target payload can alter Once/Session/Deny and the review flag, potentially bypassing the intended review-only behavior. A notification-observation capability is one possible prerequisite. The device must be unlocked for this main-activity path.

Route authorization through private, single-use handles bound to target, request, choice and review policy; derive mandatory review from trusted app state. Preserve cold-start behavior and reject forged, stale or replayed handoffs. Native verification should cover previews-disabled notifications, all choices, process restart, lock state, and expired requests. The boundary is confirmed by source inspection; no device misuse was attempted.

### R05 — Validate share URI origin before opening it

`MainActivity.kt:877–890` collects `EXTRA_STREAM`/ClipData URIs without scheme or provider-ownership checks. `:655–665` then queries and opens them using Wing's `ContentResolver`. The SEND entry point is exported. Filename sanitation and byte limits constrain the destination, not the origin's authority.

An external caller can request staging of a URI Wing can read using its own privileges, including a private-file URI or a self-owned provider URI. Subsequent user review and Send can disclose that staged data to Hermes/provider processing. **There is no claim of automatic exfiltration without user submission.** Android describes this class of confused-deputy issue in its official [ContentResolver security guidance](https://developer.android.com/privacy-and-security/risks/content-resolver).

Reject external `file:` inputs and Wing-owned provider authorities; validate allowed external content URIs and granted access before any metadata query or open. Preserve internally initiated camera/file flows through an explicit trusted path. Test with a disposable second Android app, valid grant-bearing external shares, revoked grants, and internal camera capture. Changes carry medium risk because overly broad rejection could break legitimate providers.

### R06 — Treat malformed notification extras as recoverable external input

`ChatNotifications.kt:133` constructs `JSONObject(value)` without a guard. The calls from `MainActivity.kt:299,327` have no enclosing error handling for this operation. Malformed JSON delivered to the exported activity can escape a lifecycle callback and crash the process, disrupting monitoring; unlike R04, no valid live target payload is needed.

Bound the extra's size, validate its schema/types, and discard malformed data without invoking an interaction. Catch parsing errors at the public boundary. Add behavioral native checks for malformed, oversized and wrong-typed extras, and verify valid private notification actions still work. Source confirms the unchecked exception; device crash behavior was not exercised.

### R07 — Validate preference schemas before import mutates storage

`config_backup.dart:175` checks that an encoded value agrees with its generic type tag, but not with the application's schema for that preference key. `config_backup_service.dart:155–172` validates voice preferences specifically and writes other recognized keys using the supplied value type. `main.dart:89` subsequently reads the theme using `getString`; text-size settings similarly require strings.

A codec-valid numeric `theme_mode` imports successfully and is counted as applied. An isolated production-codec/import test then reproduced a `TypeError` from `WingApp.getThemeMode`. Persistence can therefore make the next launch fail until preferences are repaired or cleared.

Define accepted type and enum/value constraints for every backed-up key, including structured/prefixed values, and validate before changing connections or preferences. Reject the backup or explicitly report skipped invalid entries; do not quietly write a value that a consumer cannot read. Test malformed known keys, unknown keys, valid enums, and a restart-equivalent read of every imported setting. Validation should complement, not replace, R02's transaction guarantees.

### R08 — Distinguish transport uncertainty from explicit mutation refusal

Regeneration and saved-prompt editing classify every `JsonRpcError` as rejection in `profile_workspace_controller.dart:3952,4046`. They restore old history and present messages such as “The conversation is unchanged.” However, actual socket closure and request expiry are also surfaced as `JsonRpcError` (`ws_client.dart:303,649`). They can occur after Hermes has accepted and truncated history.

Two isolated tests reproduced the incorrect classification using real transport-error shapes. Existing tests cover uncertainty using a generic `TimeoutException`, which misses this concrete runtime path. Other recovery machinery may later refresh state; it does not make the initial rejection and unchanged-history claim accurate.

Separate verified server refusal from transport loss or timeout. Retain an uncertain operation state, reconcile authoritative history, and avoid replaying destructive submissions. Test closure and request timeout after acceptance, explicit rejection before mutation, reconnect reconciliation, and user edits made while recovery is pending.

### R09 — Preserve stock Hermes usage date keys without assuming UTC buckets

`usage_analytics.dart:64–77` constructs a UTC-only calendar range and omits returned dates outside that range. The dashboard labels the calendar UTC at `admin_usage_dashboard.dart:497,501`. Current stock Hermes groups session starts with SQLite `date(..., 'unixepoch', 'localtime')`, as shown in the pinned [analytics router](https://github.com/NousResearch/hermes-agent/blob/ac0cfa7db94cefa90cf3e35191f38b53888b9e17/hermes_cli/web_routers/analytics.py#L85).

At a UTC-day boundary, a server in a positive-offset timezone can return tomorrow's local-date key. A production-parser reproduction showed a 150-token returned row disappearing and the constructed cells summing to zero. Negative offsets also affect range boundaries. The rolling time cutoff and date grouping are different concepts.

Preserve valid server date keys, stop labeling them UTC without a contract that supplies UTC, and ensure calendar/range summaries do not discard returned data. If the server timezone is unavailable, make that limitation explicit rather than guessing it from the phone. Test positive/negative offsets, DST, month/year rollover and partial first/last dates. Medium risk reflects changing calendar interpretation and labels together.

### R10 — Model script output runs separately from conversation sessions

`scheduled_task.dart:90–103` discards the response's `source`. All run rows navigate via `ProfileSessionKey(..., run.id)` in `admin_scheduled_task_detail_page.dart:361,399–404`.

Current stock Hermes deliberately does not write SessionDB conversations for script-only jobs. Its [cron router](https://github.com/NousResearch/hermes-agent/blob/ac0cfa7db94cefa90cf3e35191f38b53888b9e17/hermes_cli/web_routers/cron.py#L346) returns `source='cron_output'` with synthetic output-run IDs. Such a row cannot be resumed as a durable chat, so tapping it produces a failed conversation open rather than a useful run view.

Retain run kind/source in the model and only enable conversation navigation for actual sessions. Show the available output-run status/metadata; add an output viewer only through verified stock read contracts. Test mixed agent/script history, script execution-ledger rows, latest-output rows and legacy-free current response fixtures.

### R11 — Bound backup bytes and decoded structures before allocation

`config_backup_io.dart:63–66` accepts any picked file and reads all bytes into memory before UTF-8 decoding. `config_backup.dart:276` parses the complete JSON string and `:319–322` allocates decoded encryption fields. The key-stretching iteration limit at `:333` does not bound these earlier allocations.

Selecting an unrelated large archive/video, or a very large structured backup, can exhaust Android memory before a friendly invalid-backup error. The allocation path is certain; the failure threshold depends on device memory and has not been measured.

Enforce a documented shared byte budget while streaming, including when reported size is absent or misleading. Bound encoded and decoded envelope fields, connection/preference counts and relevant string lengths before expensive work. Verify exact-limit and over-limit cases, misreported file size, large plaintext/encrypted envelopes, and ordinary export/import round trips.

### R12 — Give file operations deadlines and actual cancellation

Remote file directory/text/download methods in `remote_files_client.dart:144–213` await raw dashboard operations. `connection_manager.dart:1505–1509,1526–1554` has no request/header/body deadline; byte ceilings constrain size only. Production output viewers and `deliverable_attachment.dart` retain busy state until these futures finish.

A reachable server that stalls its response can leave opening/download actions pending without a timely error/retry path. This was traced through active callers, not inferred from unused service code. No latency distribution or device stall test was measured.

Introduce a bounded transfer lifecycle with cancellation that aborts underlying I/O on timeout, owner disposal or deliberate cancel. Apply limits across authentication, headers and body, with actionable errors and deliberate retry. A bare `Future.timeout` that leaves sockets/streams alive is insufficient. Test stalled headers, stalled body, route disposal, cancellation and successful near-limit transfers.

### R13 — Reuse the app's dirty-editor guard for MCP setup

`admin_mcp_setup_page.dart:28–39` owns a substantial editable form, while its `PopScope` at `:221–222` only guards `_busy`. There is no dirty-state discard guard. Profile navigation consults route pop disposition in `workspace_profile_navigation.dart:15–17`; `admin_navigation.dart:103` remounts a new profile page.

Back or profile selection silently destroys unsaved endpoint, environment/header, OAuth and related setup input. Other administration editors already retain drafts and guard dirty navigation, making this both an actual loss of work and an inconsistent interaction.

Track meaningful dirtiness and reuse the existing discard-confirmation behavior for back, profile switching and connection switching. Keep credentials in the intended transient form lifecycle; do not persist secrets merely to retain a draft. Verify keep/discard choices, switching while busy, and empty/pristine forms.

### R14 — Guard pending mutation dialogs and their input

Saved-message editing uses default dismissible `showDialog` at `profile_workspace_screen.dart:1200`; while awaiting submission it disables Cancel but leaves the text field enabled and does not block system back/scrim dismissal. Input is captured at submission (`:1252`), but successful completion pops the dialog (`:1262`) even if the user has typed newer text. If dismissed, the mounted check at `:1260` abandons contextual failure recovery. Project mutations have the same pending-dismissal pattern in `profile_project_actions.dart:81,175–178`.

The operation can proceed after its dialog disappears, a failed attempt can lose the retained correction, and later edits can vanish after a previous value is accepted. Guard back and barrier dismissal while pending and either disable input or preserve a changed draft explicitly. Verify delayed success/failure, scrim/back gestures, edits during a pending call, and errors staying beside their owning input.

### R15 — Compile Android on pull requests, before release signing

`pr-quality.yml:51–64` runs Dart analysis and host Flutter tests. Native compilation first occurs in the release workflow at `release.yml:136`. Host tests such as `android_share_platform_contract_test.dart:20–27` assert Kotlin text markers, and renderer tests mock platform behavior; neither catches Kotlin type errors or Android manifest/build integration failures.

A native-breaking change can pass normal PR quality gates and fail at release time. Add an unsigned/debug Android build to PR CI using the documented Java/SDK toolchain. Establish a focused disposable-emulator layer for the critical native intent/share/notification boundaries. Verify no production signing credentials are required. This is a confirmed coverage omission, not a claim that the current Android build fails.

### R16 — Run the existing real diagram-isolation harness in CI

`scripts/test-diagram-preview.mjs:103–117,158–170,200–211` exercises forbidden Mermaid content, SVG scripts/network requests and HTML sandbox behavior with an actual browser. Neither reviewed workflow runs it. `docs/DIAGRAM_PREVIEWS.md:65` documents manual execution.

The renderer has meaningful security controls, but mocked host tests cannot prove browser enforcement stays intact after template/JS/dependency changes. Run the existing harness with its supported pinned Node/browser environment in CI, failing on unexpected script execution, network access or sandbox escape. Separately validate the Android WebView integration; desktop browser success is not a substitute. The harness was not run locally because compatible prerequisites were absent.

### R17 — Make responsive and conversation captures verify real fixture state

`studio_layout_test.dart:184` uses `setSurfaceSize` without matching `tester.view.physicalSize`/DPR. Its `MediaQuery` override at `:220` changes text scale only. Production's narrow header chooses its branch using `MediaQuery.sizeOf(context).width < 480` at `profile_workspace_screen.dart:594`. Fresh nominal 320 dp captures therefore render a narrow surface with the wider single-row header branch.

Separately, `studio_layout_test.dart:306–333` directly changes the chat title/model/messages without notifying the controller. Fresh “conversation” captures still show **New chat / Start a conversation**. Later typing triggers a rebuild, but does not validate the earlier artifact.

These are verification defects, **not evidence that the real phone header overflows**. Set and reset actual view metrics, assert intended MediaQuery width and narrow/wide branch, and drive populated-state changes through the UI's real notification/event path. Assert title, assistant content and absence of the greeting before exporting. Existing passing capture tests otherwise offer false confidence about those states.

### R18 — Index project membership once instead of rescanning every project

`profile_workspace_controller.dart:3012–3047` serially calls `projectSessions` for each project until a matching chat is found. `profile_gateway.dart:503–508` requests a scan limit of 5,000. An unassigned result is not remembered as completed, so opening that chat again starts over.

The pinned [stock handler](https://github.com/NousResearch/hermes-agent/blob/ac0cfa7db94cefa90cf3e35191f38b53888b9e17/tui_gateway/methods_config.py#L153) builds the project tree and then selects the requested project's sessions. With P projects, a late match or unassigned chat can cause P serial calls and repeated whole-tree builds. The lookup is asynchronous, so it does not directly block opening history, but it adds avoidable host/network work and delayed project labels.

Share an ownership-scoped membership index from a single adequate stock tree/read, with invalidation after project/session changes and a completed-unassigned marker. Respect incomplete scan coverage: absence from a truncated result must not establish unassigned status. Verify request counts across repeated opens, large project sets, membership changes, reconnect and incomplete responses. No measured server latency claim is made.

### R19 — Bound settled state without evicting live ownership

Opened chats are retained in `resource.chats` (`profile_workspace_controller.dart:2725`), while `showList` at `:3051–3056` only clears selection. `profile_workspace_registry.dart:59` retains a controller for every connection identity, and `:86–93` reconnects initialized owners even after the user has moved on. Whole-registry disposal at `:105` is the main cleanup boundary. Credential/endpoint edits intentionally create new identities.

Disk snapshots have limits, but live transcripts, idle owners and their recovery work do not have a corresponding lifetime budget. Long navigation sessions and repeated connection edits therefore accumulate retained state and can reconnect obsolete clients. The retention structure is confirmed; heap/battery impact needs a measured navigation soak.

Define ownership leases and a bounded idle-chat/owner eviction policy. Never evict active turns, approvals, queued prompts, unsaved drafts, open routes, pending notifications or recovery that still owns work. Retire superseded owners only after those obligations settle. This is a multi-day, high-risk lifecycle change: first add characterization/soak tests and explicit memory/socket/request observations, then verify active-work retention across navigation and connection edits.

### R20 — Reclaim removed browser-row notifiers

`chat_browser_data.dart:142–157` replaces visible entries/positions but only adds or updates `_values`; removed keys remain until whole-object disposal at `:483`. Archive toggles, deletions and dataset churn retain stale row payloads for the mounted browser's lifetime.

Prune obsolete notifiers once mounted listeners have safely detached, or introduce an explicit listener-aware row lifetime. Test repeated replacement/deletion/archive cycles and bounded retained row counts. Do not dispose notifiers while list rows still depend on them. This is a small, concrete cleanup separate from R19's broader owner lifecycle.

### R21 — Remove or relocate disconnected feature implementations

Import/export/part reachability from `lib/main.dart` identified 22 files outside the shipping main graph. Notable disconnected systems include `projects_repository.dart`, `chat_space_store.dart`, `quick_chat_store.dart`, `ai_search_query_rewriter.dart`, `session_search_client.dart`, `session_search_preferences.dart`, and `gateway_turn_application_controller.dart` (about 1,849 lines across these seven files). Some have extensive tests but no production construction path. Related unused projections/utilities also remain.

This is primarily cognitive and maintenance cost; Dart tree shaking means it is not automatically an APK-size or runtime-speed defect. Parallel unused implementations make it harder to identify the real project/search/turn behavior and can misdirect future fixes.

Before deletion, check supported alternate entry points and integration/performance harnesses. Remove obsolete code and dependent tests, or move intentional experiments outside shipping `lib/` with clear ownership. Keep active helpers that merely live in an older module. Verification should include main and supported alternate entry-point analysis plus the full existing suite. No replacement facade, legacy alias or compatibility layer is recommended.

### R22 — Expand hit areas while preserving approved visual geometry

The clear-filter action is constrained to 28 dp width at `profile_workspace_browser.dart:461–463`, and saved-message Edit is explicitly 40×40 at `profile_workspace_screen.dart:1121–1124`. These ordinary actions fall below the project's standard 48 dp target. Approved compact profile/Activity exceptions do not cover them.

Expand their interactive/semantic bounds while retaining compact artwork and preventing overlap with nearby content. Verify target geometry and edge taps at narrow widths and enlarged text. This does not call for replacing the established Studio visual style.

### R23 — Expose composer alternative actions to hardware keyboards

`composer_action_button.dart:274` provides screen-reader custom actions, but `:280` opens alternatives through long press only. At `:323` the underlying focusable button is disabled if its primary action is unavailable. With a running chat, empty draft and default Steer primary, Stop can be enabled while the ordinary button is disabled (`profile_workspace_screen.dart:2028–2031`).

Keyboard users cannot discover/open that action picker through the normal focus path. This is not a claim that interruption is universally impossible: `/interrupt` and some queue actions provide other paths. Provide a focusable keyboard menu/shortcut when any alternative is enabled, with clear semantics, while preserving the documented pointer gesture. Test Tab navigation, menu activation, selection and Escape in both primary-enabled and alternative-only states.

### R24 — Compare calendar dates for chat grouping

`chat_list_view.dart:215–219` computes day differences between local midnights using `Duration.inDays`. Across a spring DST transition those midnights can be 23 hours apart, producing zero days and putting yesterday's chat under Today. A deterministic `America/New_York` reproduction confirmed the 23-hour/zero-day result. Seven-day boundaries can also shift.

Compare calendar-date ordinals, for example UTC dates constructed from the local year/month/day components. Keep the timestamp's original timezone interpretation for display. Test spring/fall transitions, Yesterday and the Previous 7 days boundary. Fix risk is low.

### R25 — Keep the Custom setup address label complete at large text

The genuine 320 dp / 200% text connection captures in both themes show “Chat gateway b…” for the empty field at `connection_setup_screen.dart:1339`. The full “Chat gateway base address” instruction is lost at the moment the user needs it.

Use the existing enlarged-text external-label pattern or a shorter complete label. Verify the empty, focused, filled and invalid states at enlarged text in both themes. Other inspected connection/administration forms remained readable and scrollable; no additional blocking visual defect was established.

### R26 — Restore per-connection preferences into the destination namespace

`config_backup_service.dart:75` includes `session_visibility_v1_` preferences and imports their keys verbatim. The active controller derives `_visibilityKey` from `connectionIdentity` (`profile_workspace_controller.dart:529`). That identity is an HMAC using a randomly generated device-local secure-storage key (`profile_connection_identity.dart:12,29–34,78`), which configuration backup does not export.

The same restored connection on another device therefore gets a different identity, and its imported visibility preference remains under an unread old key. The import can count the setting as restored while the browser falls back to its default. Same-device restoration does not demonstrate portability.

Represent portable per-connection preferences by logical backup ownership and remap them to the destination identity. Keep the identity secret device-local and do not weaken owner checks. This may require a clean backup-format change; any backward-compatibility handling needs explicit approval under the workspace agreement. Test separate source/destination identity stores, identical connection settings, multiple connections, and no cross-owner preference inheritance.

## Cleanliness, simplicity, and reuse

The project has useful boundaries already: immutable connection/profile ownership, scoped gateway/repository APIs, explicit uncertain-operation handling in several administration flows, bounded disk snapshots, and distinct models for many concepts. Documentation captures subtle user-facing decisions rather than leaving reviewers to guess them.

The main maintenance pressure is concentrated orchestration: `profile_workspace_controller.dart` is about 7,082 lines, its screen about 2,632, and `main.dart` about 1,551. File size alone is not a defect and a broad rewrite is not justified. Improve these seams incrementally around demonstrated problems:

1. **Authenticated transport policy:** R01 demonstrates drift between similar connection paths. Share origin/redirect/deadline behavior behind a small transport boundary, while keeping protocol-specific commands separate.
2. **External configuration validation and import commit:** R02/R07/R11 belong to a cohesive importer that validates, bounds, stages and commits data. UI should receive a typed outcome rather than manage storage internals.
3. **Editor lifecycle:** R13/R14 justify reusing dirty/pending-navigation guards. Keep draft ownership and error retention explicit instead of constructing slightly different flags in every form.
4. **Workspace state lifetime and projection:** R18–R20 justify separating membership indexing and settled-state retention from live turn ownership. Characterize behavior first; preserve active work and complete browser filtering semantics.
5. **Remove duplicate inactive systems before extracting more abstractions:** R21 reduces ambiguity and makes the remaining production graph easier to navigate.

Avoid creating interfaces simply because a file is large or adding generic base classes around unrelated administration operations. Prefer a concrete boundary with a small interface and internalized invariants that currently require repeated caller discipline.

## What is working well

- Static analysis and the substantial existing suite pass; release scripts also have real tests.
- Connection identities bind endpoint and credential configuration, protecting against accidental retargeting. That protection should survive lifecycle cleanup.
- Several mutation flows distinguish unconfirmed writes and avoid blind replay; the edit/regenerate issue is a specific inconsistency to correct.
- Most inspected forms support growing text, scrollability and retained inline failures. Fresh connection and administration captures show coherent light/dark treatment.
- HTML/SVG/Mermaid previews contain meaningful isolation controls: sandbox/CSP, restricted navigation/resource access, and no arbitrary native bridge. The finding is missing continuous verification, not a demonstrated renderer execution exploit.
- Credential-sensitive defaults, backup choices, and upstream constraints are documented. No current direct dependency upgrade or committed secret-marker finding was established by the checks performed.

## Considered and rejected / by design

- **Latest-message recency reads:** Per-session reads are intentional and batched to distinguish actual message activity from heartbeat timestamps. A generic “remove N+1” rewrite would break intended recency.
- **Complete browser history:** Full pagination supports complete filters/totals. Replacing it with a partial lazy dataset would change product semantics; optimize rendering/indexing without silently narrowing results.
- **Root back behavior:** Opening the drawer before exit is documented app-shell behavior, not an accidental navigation bug.
- **Compact Studio controls:** Approved profile and Activity geometry exceptions are deliberate. R22 is limited to ordinary actions outside those exceptions.
- **Active controller retention:** Preserving running turns across navigation and connection edits is required. R19 concerns unbounded settled/obsolete retention, not retaining active work.
- **All transports leak on redirect:** Rejected. Ordinary chat WebSockets and dashboard/cloud transports have protections. R01 identifies the reachable console path that diverges.
- **Plaintext backups or local HTTP as automatic vulnerabilities:** These are explicit, disclosed product choices; no blanket removal recommendation was made.
- **Unused AI rewriter runtime vulnerability:** Rejected as a production finding because the weaker path is disconnected from the shipping main graph; consider it only if intentionally activated.
- **Screenshot header overflow:** Rejected as a production claim because the responsive fixture metrics were wrong. R17 records the verification defect.
- **Every script-run ID is a session ID:** Rejected against current stock upstream; this is the basis of R10 rather than a request for server customization.
- **Historical upstream limitations still hold today:** Not assumed. Existing docs are useful leads, but live-provider/backend behavior was not reverified. Do not present old known limitations as newly confirmed client bugs.
- **No advisories means safe dependencies:** Rejected. The OSV result excludes a full Gradle/vendor-JS/platform supply-chain audit and cannot establish exploitability absence.

## Release sequence and remaining acceptance work

1. **Close the three P1 blockers first.** Add boundary regression coverage for redirects, partial import failures and explicit project destinations; preserve stock upstream behavior.
2. **Close the external-input and recovery holes.** R04–R08 and R11 need focused tests, including native behavioral checks. Validate the full import before mutation and never replay uncertain destructive actions.
3. **Restore credible release gates.** R15–R17 should precede further native/visual changes. Compile Android in PR CI and run real renderer tests. Correct the screenshot fixtures before treating screenshots as responsive acceptance evidence.
4. **Fix everyday visible behavior.** R09/R10/R12–R14 and R22–R26 have direct user consequences. Test against current stock Hermes and exercise keyboard/accessibility flows.
5. **Measure and address scale.** Establish representative long-history/project datasets and navigation/connection-edit soaks, then apply R18–R20. Verify memory plateaus, obsolete socket cleanup, server request counts and profile-build frame times on representative phones. R19 requires the most careful characterization.
6. **Simplify after behavior is protected.** Remove disconnected code and extract the demonstrated shared seams; rerun the existing suite once changes land. Do not front-load a large architecture rewrite.

Before claiming public readiness, run the documented integration scenarios on a disposable Android phone/emulator and a pinned unmodified Hermes deployment: initial connection/authentication, project selection/recovery, chat/approval/queue lifecycle, process death/relaunch, network loss/reconnect, notification choices while locked/unlocked, sharing/camera/file viewers, stock scheduled script runs, server timezone analytics, and encrypted/plain backup round trips across devices.

Perform a human UX pass with TalkBack, Switch Access or keyboard navigation, real IME/system insets, narrow screens, 200% text, light/dark themes, permission denials and offline transitions. Host captures reserve keyboard space but do not exercise a real IME. Measure release/profile builds on a lower-memory phone and a representative current phone, including long transcripts, diagram-heavy output, background monitoring and repeat navigation. Inspect signing/build/store artifacts separately; the metadata check is not a release certification.

## Optional follow-on direction

These are maintenance options, not additional bugs or prerequisites for a feature expansion:

- **A stock-Hermes contract lane.** The current-version mismatches in R03/R09/R10 and the existing `docs/TESTING.md` / upstream limitation documentation support a small pinned-upstream acceptance lane. A scheduled current-main comparison could reveal contract drift earlier, at the cost of fixture/deployment upkeep. Keep current stock support direct; do not turn this into a compatibility matrix without approval.
- **Explicit performance acceptance budgets.** The existing `docs/PERFORMANCE.md`, retained-owner design and complete-history browser make dataset-based memory/request/frame budgets valuable. Start with measured baselines and a repeatable soak rather than adding speculative micro-optimizations. Budget choices need representative target devices and user datasets.

No implementation plans were generated or fixes dispatched. The recommended first implementation batch is R01–R03, followed by the import/native-input/recovery protections and CI verification gaps.
