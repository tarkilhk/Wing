# Wing codebase review: correctness and ease of change

Reviewed 3 October 2026 against `3eef349863081afcef36ee283df4b766535dcf43`, including the 14 existing modified files. The diff SHA-256 at baseline verification was `2fee172485d9c270a739fdf05935031ba09c73f2d47ff14a2774e31f40b04b31`. Existing controller-test work advanced during final bookkeeping, producing diff hash `a42374d1e496b52991f07a46c73917647f0b279b067368f5968d2f743e07737b`; the cited defect paths were rechecked. This report is the only repository addition from the review; source and existing tests were not edited by the review.

## Assessment

Wing has a substantial, passing verification baseline and useful ownership models. Its main obstacle to future changes is concentrated orchestration: multiple meanings of chat state, several competing chat implementations, and domain behavior hidden inside widget libraries. Those problems have concrete consequences, including stale responses replacing live state and draft edits bypassing persistence.

**Recommended direction: delete the inactive implementations, give each mutable operation a clear owner, and make the existing domain seams authoritative.** Protect the demonstrated failure cases before restructuring the central controller. A file split alone would distribute the same state-management burden across more files.

This review contains **18 vetted findings**: eight correctness/contract/persistence defects, three structural simplifications, three native/image reliability issues, two localized algorithmic improvements, one verification gap, and one transcript performance investigation. Three defects were reproduced with temporary regression tests. The report distinguishes demonstrated behavior from costs whose device impact still needs measurement.

## Scope and method

The application repository is the nested `hermes-android/` checkout. Production sources comprise 252 Dart files, approximately 72,086 lines, and 16 Kotlin files, approximately 3,650 lines. There are 334 Dart host-test files and 51 Dart integration-test files. This was a whole-project, risk-weighted audit; it does not imply equal inspection of every line.

Four reviewer roles were used, with at most three reviewers running alongside the lead. They completed eight specialized passes: architecture/change locality; correctness/concurrency; security/native trust; performance/resources; verification/developer tooling; current-upstream contracts; UI/editor lifecycle; and persistence/schema ownership. The lead read the cited implementation paths, checked callers and constraints, rejected stale findings, and ran verification. Reviewer roles share the available model; this is independent-context review, not a claim of multi-model consensus.

Reviewed areas include workspace/session ownership, events/resume/reconnect, drafts/outbox, browser mutations, projects/history, notifications, authenticated transports, backup/import, external sharing and file viewers, Markdown preparation, transcript rendering, administration, scheduled tasks, voice, CI/release tooling, and related design/domain/acceptance documentation. Sibling prototype checkouts and the backend checkout were references rather than application audit targets.

The current stock Hermes reference was verified through GitHub and pinned to [`bd0affe5e5f723579df8902852f5d0c47795f355`](https://github.com/NousResearch/hermes-agent/commit/bd0affe5e5f723579df8902852f5d0c47795f355). Contract checks used that revision, including the method registry, all 29 gateway method modules, relevant typed contracts, and dashboard session/file/audio/cron routes. Client changes must continue to target unmodified upstream Hermes. No deployment, backend patch, custom endpoint, or compatibility behavior is proposed.

### Official pstack reference

The initial fork reference was corrected after the user's clarification. `poteto/pstack` returned 404 through both public web access and the available GitHub connector. The official accessible source is [Lauren Tan's pstack in `cursor/plugins`](https://github.com/cursor/plugins/tree/main/pstack), whose [manifest](https://github.com/cursor/plugins/blob/main/pstack/.cursor-plugin/plugin.json) identifies Lauren as its author. The review used that official source's [code-quality lens](https://github.com/cursor/plugins/blob/main/pstack/skills/interrogate/references/code-quality-review.md) and [lead judgment](https://github.com/cursor/plugins/blob/main/pstack/skills/interrogate/references/lead-judgment.md), without installing a plugin.

Principles that changed the recommendations:

- [Subtract Before You Add](https://github.com/cursor/plugins/blob/main/pstack/skills/principle-subtract-before-you-add/SKILL.md): remove inactive transports and the experimental fixture protocol before extracting more layers.
- [Minimize Reader Load](https://github.com/cursor/plugins/blob/main/pstack/skills/principle-minimize-reader-load/SKILL.md): judge hidden state and indirection, rather than using controller size as the reason for a rewrite.
- [Model the Domain](https://github.com/cursor/plugins/blob/main/pstack/skills/principle-model-the-domain/SKILL.md): preserve execution, connectivity and pending decisions as distinct facts; derive their presentation.
- [Boundary Discipline](https://github.com/cursor/plugins/blob/main/pstack/skills/principle-boundary-discipline/SKILL.md): keep transport parsing and provider checks out of widget-owned behavior, and account for the actual stock ownership contract.
- [Test Behavior, Not Implementation](https://github.com/cursor/plugins/blob/main/pstack/skills/principle-test-behavior-not-implementation/SKILL.md): reproduce through the active controller and real task route; retain tests of shipping behavior when deleting inactive code.

## Verification

Commands ran from the application checkout with the workspace toolchain. Flutter's test socket and Gradle's lock service required approved local-socket sandbox exceptions. Initial socket-denied runs were infrastructure failures, not application failures.

| Check | Result | Limit |
| --- | --- | --- |
| `flutter analyze --no-pub --fatal-infos` | Passed, no issues | Static checks |
| `flutter test --no-pub --reporter expanded` | **2,816 passed, 17 skipped** | Existing fixtures; skipped opt-in scenarios provide no acceptance evidence |
| Final focused controller suite after concurrent test edits | **106 passed** | Rechecks the changed test file; the whole-suite count above belongs to its earlier snapshot |
| `python3 -m unittest discover -s scripts/tests -v` | **30 passed** | Release tooling |
| `python3 -m unittest discover -s tools/qa -p 'test_*.py' -v` | **67 passed** | Offline QA tooling, without device access |
| `python3 scripts/release.py check` | Passed | Release metadata consistency |
| `./android/gradlew -p android :app:testDebugUnitTest --rerun --offline --no-daemon` | **9 passed**, no failures/errors/skips | Fresh execution of native JVM boundary tests; no emulator behavior |
| Temporary resume/shared-draft regressions | **Both failed desired-behavior assertions** | Confirms findings D01/D02 on the current code |
| Temporary real task-route regression | **Failed desired sparse-update assertion** | Confirms D05: name-only save also submits old prompt |
| Isolated current-upstream cron owner resolver | Passed its demonstration assertion | Alpha request resolves Beta after ownership changes; no live mutation |
| `git diff --check` | Passed | Existing patch whitespace |

Logs: `/tmp/wing-clean-review-analyze.log`, `/tmp/wing-clean-review-full-tests.log`, `/tmp/wing-clean-review-controller-final.log`, `/tmp/wing-clean-review-release-tests.log`, `/tmp/wing-clean-review-qa-tests.log`, `/tmp/wing-clean-review-native-tests.log`, and `/tmp/wing-clean-review-scheduled-repro.log`. Temporary regression sources: `/tmp/wing_resume_review_test.dart` and `/tmp/wing_scheduled_editor_review_test.dart`. These are session evidence, not permanent regression coverage.

No fresh visual captures, live gateway/provider journeys, emulator/device interaction, release APK build/signing/store checks, or physical-device performance measurements were performed. iOS runtime behavior, full transitive dependency/advisory/license analysis, and complete secret-history scanning were outside this pass. Performance findings below describe inspected work placement/complexity, not measured phone latency, memory, battery, or ANR frequency.

## Priorities

Effort includes focused tests: S = hours, M = about a day, L = several days. Risk describes the change, not the current defect. H/M confidence is confidence in the cited issue, not its frequency. P2 denotes a material issue; P3 denotes maintenance or scale work. No P0/P1 security vulnerability was established in this pass.

| ID | Finding | Category | Priority | Effort | Change risk | Confidence |
| --- | --- | --- | --- | --- | --- | --- |
| D01 | Older resume overwrites newer live turn | Correctness | P2 | M | Medium | H, reproduced |
| D02 | Failed share save rolls back newer typed text | Correctness | P2 | S | Low | H, reproduced |
| D05 | Task refresh changes the edit baseline and overwrites newer fields | Correctness | P2 | M | Medium | H, reproduced |
| D03 | Slash completion bypasses durable draft updates | Correctness | P2 | S | Low | H |
| D04 | Confirmed deletion is withheld after local cleanup failure | Correctness | P2 | M | Medium | H |
| D06 | Cached task IDs can mutate a different profile in current stock Hermes | Contract | P2 | M | Medium | H |
| D08 | Reading snapshots lose hidden/notice presentation semantics | Persistence | P2 | S | Low | H |
| A01 | Delete inactive chat implementations and their state/tests | Architecture | P3 | M | Low–medium | H |
| V01 | Gate the existing offline QA suites in CI | Verification | P2 | S | Low | H |
| A03 | Relocate widget-owned domain types and diagnostics | Architecture | P3 | M | Low–medium | H |
| D07 / A02 | Separate execution, transport and pending-input facts | Correctness / architecture | P2 | L | High | H for divergence; M for event frequency |
| N01 | Bound image allocation and move sanitation off the UI isolate | Security / performance | P2 | M | Medium | H for work placement/bounds |
| N02 | A stalled provider blocks all native intake operations | Native reliability | P2 | M | Medium | H, source traced |
| N03 | Voice file transfers execute on Android's main thread | Native performance | P2 | M | Medium | H for thread placement |
| V02 | Remove the unused recovery experiment from the normal gateway fixture | Test architecture | P3 | M | Low–medium | H |
| P01 | Fence scanning repeatedly copies the remaining document | Performance | P3 | S | Low | H for complexity |
| P02 | Empty-project grouping rescans all matching sessions per project | Performance | P3 | S | Low | H for complexity |
| P03 | Rebuilds repeat history-wide transcript structure work | Performance investigation | P3 | M | Medium | H for work; device benefit unmeasured |

## Correctness and persistence findings

### D01 — Preserve newer events when a resume response arrives

[The cached-chat open path](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:3228) awaits resume, then [hydrates without an event revision check](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:3253). Hydration replaces live text and execution status; opening then [clears streaming when that status appears settled](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:3283). Reconnect and queue-resume paths use the same policy.

The reproduction holds an idle response, delivers a new `message.start` and delta, then releases the older response. Expected status is running; actual status becomes completed and the live text disappears. Capture identity/runtime/event revision before reading and reconcile only snapshot fields still current. Preserve legitimate runtime changes. Add deterministic held-response cases for open, reconnect and queue recovery at the existing controller seam.

### D02 — Make shared-draft rollback respect newer edits

[Share staging](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:4099) mutates the composer and awaits storage. Its [failure handler](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:4104) restores the original text and attachments unconditionally, while ordinary draft edits remain allowed.

The reproduction types fresh text during the pending write, then fails it. The composer returns to its original text. Give the merge a revision/ownership token and roll back only changes it still owns. Preserve newer attachment references during cleanup. Test changes during persistence as well as preparation, using the injectable draft store.

### D03 — Use the durable draft interface for slash completion

[Completion selection](/home/dev/projects/hermes-android/hermes-android/lib/core/widgets/slash_command_suggestions.dart:113) directly assigns `chat.draft` and programmatically updates the text controller. Flutter does not invoke the [ordinary `onChanged` persistence callback](/home/dev/projects/hermes-android/hermes-android/lib/core/screens/profile_workspace_screen.dart:1718) for that programmatic change. The canonical [draft update method](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:4032) also owns replacement coordination, uncertainty and composer notifications.

After selecting a completion and terminating before another edit/send, restoration can recover the old prefix. Route the edit through the existing update method or a narrow commit callback. Test selection, saved-draft recreation, save failure, Unicode offsets and retained suffixes; the existing completion test checks only in-memory insertion.

### D04 — Publish acknowledged deletion before fallible local cleanup

[Server deletion](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:3596) completes before [draft removal](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:3634). If preference persistence throws, the deletion tombstone, cached-chat removal and [connection-wide browser mutation](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:3662) never happen. The [draft store explicitly propagates failed writes](/home/dev/projects/hermes-android/hermes-android/lib/core/services/composer_draft_store.dart:209).

Commit the confirmed server outcome to every client projection, then track local cleanup separately. Preserve recoverable unsent work without presenting the deleted server conversation as available. Inject failed draft removal after successful DELETE and assert the browser/chat state stays deleted, cleanup is recoverable, and no retry repeats the destructive write. This finding does not rely on ordinary file-removal errors, which the attachment helper already handles.

### D05 — Keep task edit baselines stable across refresh

[The real task route](/home/dev/projects/hermes-android/hermes-android/lib/core/screens/administration/scheduled_task_widgets.dart:387) supplies the latest refreshed task on every controller notification. The editor's [text controllers](/home/dev/projects/hermes-android/hermes-android/lib/core/screens/administration/admin_scheduled_task_editor_page.dart:29) and selection fields retain their initial values, but [save uses the new `widget.original`](/home/dev/projects/hermes-android/hermes-android/lib/core/screens/administration/admin_scheduled_task_editor_page.dart:962). [Changed-field calculation](/home/dev/projects/hermes-android/hermes-android/lib/core/models/scheduled_task.dart:71) consequently mistakes old untouched fields for edits.

The real-route reproduction opens prompt A, refreshes to external prompt B, edits only the name, and saves. The request also sends A, undoing B. Capture the opening edit baseline, track user changes relative to it, and compare edited fields with current server observations for conflicts. Cover destinations/model/provider and unchanged interval/one-shot schedules. The existing sparse-edit test pumps a fixed original and misses the route-refresh seam.

### D06 — Respect actual scheduled-task ownership

[Task reads and writes](/home/dev/projects/hermes-android/hermes-android/lib/core/services/scheduled_tasks_repository.dart:11) do not validate the returned profile or refreshed scoped membership. [Actions use cached task IDs](/home/dev/projects/hermes-android/hermes-android/lib/core/services/scheduled_tasks_controller.dart:225). Current stock [cron ownership resolution](https://github.com/NousResearch/hermes-agent/blob/bd0affe5e5f723579df8902852f5d0c47795f355/hermes_cli/web_routers/cron.py#L79) treats `profile` as a hint and searches other profiles when the job is absent there; its mutation helpers act on the resolved owner.

A task moved Alpha → Beta while Alpha's editor is open can be updated/run/deleted in Beta while Wing labels Alpha. Validate response ownership and refresh explicit scoped membership before a cached mutation; refuse already-stale ownership and retain uncertainty if an acknowledgement contradicts it. Test moved jobs, same-owner jobs, duplicate IDs, missing membership and failed preflight.

**Stock limitation:** this API has no atomic expected-owner condition. Preflight cannot eliminate a move between checking and dispatch. Any client-only design must make that remaining limit explicit; a scoped query alone cannot promise strict ownership. No backend patch is an acceptable remedy under this project's constraint.

### D07 / A02 — Separate execution, connectivity and pending input

[One status enum](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:89) combines all three. [Activity classification](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:393) derives input attention from that status. [Turn completion](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:6791) terminalizes it while deliberately retaining independent input requests. The [browser classifier](/home/dev/projects/hermes-android/hermes-android/lib/core/models/chat_list_view.dart:22) omits direct approval/secure-input checks, while [monitoring](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_notifications.dart:25) checks them.

A completed turn with a retained approval/secure request can appear Idle/Unread or Working while monitoring says it needs input. [Clearing attention](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:6024) also assigns running without an independent execution fact.

Give execution outcome, transport availability and pending requests distinct ownership. Derive browser/Recents/monitoring attention from one pending-input projection. Characterize completion/error/interruption with each retained input kind, last-input resolution after completion, recovery while waiting, child work, composer availability and monitoring lifetime. Then remove the compensating status substitutions. This is a behavior-sensitive redesign and should follow the small durability fixes rather than lead them.

### D08 — Preserve display semantics in offline snapshots

[Snapshot projection](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:1409) keeps only id/role/content/timestamp; [restoration](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:1360) puts those rows straight back into history. [Hidden-row suppression](/home/dev/projects/hermes-android/hermes-android/lib/core/models/answer_versions.dart:110) and [notice classification](/home/dev/projects/hermes-android/hermes-android/lib/core/models/transcript_notice.dart:8) require omitted display fields. Stock [prompt handling](https://github.com/NousResearch/hermes-agent/blob/bd0affe5e5f723579df8902852f5d0c47795f355/tui_gateway/methods_prompt.py#L663) supports hidden submissions.

Restarting offline can reveal ordinary-content hidden rows and render typed notices as messages until refresh. Define a bounded reading-row projection preserving display kind/content and the metadata needed for presentation. Keep runtime state and decisions out of reading restoration. Roundtrip hidden rows, typed notices, delegation counts/results and steering while asserting snapshots cannot enable mutations.

## Structural simplifications

### A01 — Delete the inactive chat implementations

[`ApiClient`](/home/dev/projects/hermes-android/hermes-android/lib/core/services/connection_manager.dart:948), [`GatewayChatClient`](/home/dev/projects/hermes-android/hermes-android/lib/core/services/connection_manager.dart:1158), and [high-level `WsClient` streaming/chat methods](/home/dev/projects/hermes-android/hermes-android/lib/core/services/ws_client.dart:646) have test callers but no shipping/integration callers. Their supporting stream/listener state survives inside reachable files. The production [ProfileGateway](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_gateway.dart:291) uses ordinary RPC sends and pushed events.

Roughly a thousand lines offer competing answers to where chat behavior lives. Their semantics diverge: the unused submit method waits for terminal completion and does not implement the active outbox's queued acceptance path. This is a practical agent-navigation hazard: changing a well-tested method may have no product effect.

Delete inactive classes/members and now-unnecessary state. Keep socket authentication, greeting, RPC correlation, event parsing and close behavior. Move applicable assertions to the active gateway/controller seam; remove tests protecting only deleted behavior. Verify caller searches, transport/approval tests, outbox/history tests and the full suite. The September review removed disconnected files; this is additional member-level dead code that whole-file reachability cannot find.

### A03 — Put domain types and retained diagnostics in their owning modules

The [workspace controller imports widget-owned selection types](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:42). [Model identity and parsing](/home/dev/projects/hermes-android/hermes-android/lib/core/widgets/model_chooser.dart:8) live beside rendering. [Retained health imports a widget library](/home/dev/projects/hermes-android/hermes-android/lib/core/services/administration_health_session.dart:7) for its [diagnostics controller](/home/dev/projects/hermes-android/hermes-android/lib/core/widgets/profile_diagnostics_panel.dart:12), which imports the workspace controller. This forms a service → widget → service cycle.

Move model identity/selection to the existing models organization and parsing to the consuming domain/gateway module. Move provider-check execution and typed observations into the existing controller/services organization. Let widgets render a small observation interface and let diagnostics accept the scoped gateway it actually needs. Verify intelligence, diagnostics and retained-health behavior, then confirm services/models no longer import widgets. This relocates existing ownership and reduces coupling without adding a generic repository layer.

### V02 — Remove the unused experimental recovery protocol from the normal fixture

The [fake gateway's greeting](/home/dev/projects/hermes-android/hermes-android/tools/fake_gateway/fake_gateway.py:1509) always advertises the [experimental ledger](/home/dev/projects/hermes-android/hermes-android/tools/fake_gateway/turn_recovery_contract.py:198), and dispatch routes its methods before ordinary handling. It exposes `session.open`, `turn.reconcile`, versioned prompt submission and client-turn correlation. The normal probe self-tests this separate protocol.

Independent pinned-upstream inspection found none of those three names in all 29 method modules. Stock [RPC dispatch](https://github.com/NousResearch/hermes-agent/blob/bd0affe5e5f723579df8902852f5d0c47795f355/tui_gateway/rpc_dispatch.py#L23) rejects unknown methods; [the prompt contract](https://github.com/NousResearch/hermes-agent/blob/bd0affe5e5f723579df8902852f5d0c47795f355/tui_gateway/contracts/prompt_voice.py#L26) has no client-turn idempotency key.

The ledger's opening disclaimer correctly excludes production acceptance, so this is a disconnected experiment coupled to the ordinary fixture, not a shipping contract failure. Remove its 976-line ledger, custom greeting/dispatch and dedicated probes. Preserve actual stock methods and documented deterministic disconnect scenarios. Test the remaining fixture through active client interfaces, with unsupported methods rejected, and record the inspected upstream revision.

## Native and performance findings

### N01 — Bound decoded images and perform sanitation in a worker

[Attachment preparation](/home/dev/projects/hermes-android/hermes-android/lib/core/services/attachment_draft_service.dart:191) bounds compressed bytes, then [synchronously decodes/orients/encodes](/home/dev/projects/hermes-android/hermes-android/lib/core/services/attachment_draft_service.dart:210) before the next await. Selection, clipboard and reviewed shares call this shipping path.

Ordinary large photos block Flutter processing during sanitation. Small compressed inputs can require decoded allocations far beyond the byte budget. Inspect dimensions/frame count and decoded allocation budget before full decoding; transfer image processing to a worker. Preserve orientation, metadata stripping, output formats and file/draft ownership. Test bounds before allocation, rotated inputs, aggregate budgets, failed/cancelled work and orphan cleanup. Actual phone latency/memory thresholds remain unmeasured. Security and performance reviewers independently identified this issue; they are consolidated here.

### N02 — Isolate stalled content providers from queue transactions

[One process-wide executor](/home/dev/projects/hermes-android/hermes-android/android/app/src/main/kotlin/com/tarkilhk/wing/MainActivity.kt:996) handles shares, acknowledgements, camera and delivered files. External [provider open/read calls](/home/dev/projects/hermes-android/hermes-android/android/app/src/main/kotlin/com/tarkilhk/wing/MainActivity.kt:670) have no elapsed deadline.

A granted slow/broken provider can block every later intake operation; activity recreation preserves the executor. Separate cancellable provider acquisition/copy from serialized queue commits. Bound deadlines/pending work, close acquired resources, and prevent late commits after timeout. Verify with a disposable stalled provider, then demonstrate subsequent share/discard/camera/output operations still work and batch rollback cleans staged files. Merely timing out the caller while leaving the shared worker blocked would not fix the root cause.

### N03 — Move voice file transfer off Android's main thread

[The voice channel](/home/dev/projects/hermes-android/hermes-android/android/app/src/main/kotlin/com/tarkilhk/wing/VoiceChannel.kt:19) uses the default main-thread handler. [Finishing capture reads the entire file](/home/dev/projects/hermes-android/hermes-android/android/app/src/main/kotlin/com/tarkilhk/wing/VoiceCapture.kt:129), and [playback writes it synchronously](/home/dev/projects/hermes-android/hermes-android/android/app/src/main/kotlin/com/tarkilhk/wing/VoicePlayback.kt:129), with an allowed 25 MiB bound. Async player preparation does not move the preceding write.

Keep player/recorder transitions on their required thread, but use bounded background file transfer and generation-checked completion. Existing media/PDF channels provide a local pattern. Verify native thread assertions, pause/destruction/cancellation, storage failure and consecutive requests. Device pause duration is unmeasured.

### P01 — Search Markdown fences using offsets

[Opening search](/home/dev/projects/hermes-android/hermes-android/lib/core/services/markdown_segments.dart:43) and [closing search](/home/dev/projects/hermes-android/hermes-android/lib/core/services/markdown_segments.dart:52) create remaining-document substrings for every fence. With N characters and F fences, copied character volume is O(N × F); dense documents approach quadratic allocation. One expensive parse also delays other messages on the shared worker.

Search the original string from absolute offsets and create substrings only for emitted segments. Preserve indentation, variable backtick/tilde lengths, CRLF and unfinished grammar; offset searching must respect original line boundaries. Use existing scanner tests and a dense synthetic fixture. Establish scaling under the opt-in/private measurement procedure rather than brittle elapsed-time assertions.

### P02 — Index occupied projects once per arrangement

[Project grouping](/home/dev/projects/hermes-android/hermes-android/lib/core/screens/profile_workspace_browser.dart:264) checks `matches.any` inside the project loop: up to P × S comparisons on the UI isolate. Builds repeat this even when only browser presentation changes.

Build one occupied-project-key set, preserving empty-group eligibility with O(P + S) membership work. Test multiple profiles, Home, populated/empty projects and filters. This is separate from the previously fixed server membership-tree scan.

### P03 — Investigate reuse of settled transcript structure

[Live presentation](/home/dev/projects/hermes-android/hermes-android/lib/core/services/profile_workspace_controller.dart:1318) is bounded to ten updates per second, but [transcript builds](/home/dev/projects/hermes-android/hermes-android/lib/core/screens/profile_transcript.dart:393) copy/regroup loaded history and [rebuild identity/key maps](/home/dev/projects/hermes-android/hermes-android/lib/core/screens/profile_transcript.dart:444) on each update.

The multiple O(H) passes are real; whether they dominate representative phone workloads needs profiling. Treat this as **consider/investigate**, not a reason to immediately replace rendering. First count structural work with long loaded history, then introduce saved-structure invalidation and tail-only reconciliation if justified. Protect pagination, activity merging, global identities, expansion/selection, answer handoffs and reader/notification anchors. Keep complete history semantics.

## Verification improvement

### V01 — Run the existing offline QA tests in CI

[PR discovery](/home/dev/projects/hermes-android/hermes-android/.github/workflows/pr-quality.yml:61) covers `scripts/tests`; [release discovery](/home/dev/projects/hermes-android/hermes-android/.github/workflows/release.yml:102) covers the same release-tool group. Neither invokes the six `tools/qa/test_*.py` modules, including [capture privacy/fail-closed checks](/home/dev/projects/hermes-android/hermes-android/tools/qa/test_phone_performance_capture.py:39) and [comparison invariants](/home/dev/projects/hermes-android/hermes-android/tools/qa/test_compare_workspace_replays.py:84).

All 67 tests passed independently in this review. Add `python3 -m unittest discover -s tools/qa -p 'test_*.py' -v` to the PR/relevant release gates and contributor commands. It requires synthetic data and mocks, not ADB, credentials or private traces. Assert a failing test fails the workflow. Flutter instrumentation tests cover a separate implementation and cannot replace this gate.

## Cleanup sequence

1. **Protect and fix local durability:** D02, D03 and D08. They have small interfaces and limited blast radius. Add their missing behavioral regressions.
2. **Close stale-operation defects:** D01, D04 and D05, with held-response/failed-storage/real-route tests. Resolve the product limitation and stale-owner checks for D06.
3. **Delete ambiguity:** A01 and V02, independently. Keep active transport/outbox/fixture behavior protected; remove the unused code and its dedicated tests together. Add V01's existing offline gate.
4. **Relocate existing ownership:** A03, then design D07/A02 around explicit state dimensions. Establish combined composer/browser/monitoring characterization before the larger state change.
5. **Improve resource locality:** N01–N03 with cancellation/lifecycle tests and disposable-native acceptance. Apply P01/P02 as localized simplifications. Investigate P03 using the existing performance procedure before committing to a larger rendering refactor.

Each batch should finish with analysis and its focused tests. Run the full host suite once the batch is ready; run native JVM tests for Kotlin changes and actual emulator acceptance for provider/voice/foreground-service behavior. A clean test run is evidence for its exercised behavior, not proof of device performance or live server correctness.

No implementation tasks, commits, pushes or deployments were dispatched. These are review recommendations; dedicated implementation plans can be selected from this report without repeating the audit.

## Reconciliation and rejected findings

The September review and its implementation-progress record were used as leads, then checked against current code. The prior credential redirect, secure import, notification handle/schema, external share-origin, backup bounds/preference schema, explicit project destination, uncertainty handling, idle-owner retention, server membership indexing, browser notifier cleanup, dirty-editor guards, pending-dialog guards and native/renderer CI fixes are present. They were not republished as current defects. This pass's member-level dead code, omitted offline QA gate and snapshot display projection are distinct from those earlier items.

Rejected or deferred:

- A broad controller split justified only by its 7,827-line size. Change ownership and invariants justify restructuring; size alone does not.
- A universal state-management framework or generic base repository. Existing modules can own the demonstrated seams.
- Removing complete browser history, recency batches or active-turn retention. These implement documented behavior.
- Calling the inactive transport's weaknesses shipping vulnerabilities. Its production inactivity is the cleanup finding.
- Treating the fake recovery protocol as an active Wing runtime contract. The client does not call it; the fixture disclaimer is acknowledged.
- Blanket objections to disclosed HTTP servers or optional plaintext exports. No new disclosure vulnerability was established.
- Treating source-string manifest tests as inherently worthless. Real native/device layers already complement them.
- Claiming observed phone performance improvements from source inspection. The algorithm/thread findings require their stated workload/device checks.
- Calling retained voice saves after route disposal a resource leak. Captured ownership and leases intentionally allow completion.
- Speculative atomic-loss findings in the secure journal, draft transfer and notification ledger without a demonstrated reachable sequence.

Future product expansion was omitted deliberately: the requested outcome is a smaller, clearer and safer-to-change codebase. The highest-value next work is the concrete simplification and behavior protection above.
