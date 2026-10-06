# Whole-checkout dead-code inventory

## Current source and root disposition

The accepted production cleanup audit snapshot contains **1,500 authored files, 358 production
Dart files, 348 libraries and 143 views**, covering 96,058 production lines.
Ownership migrations and the fresh full-source/root review are complete for this
snapshot. There are 809 exact retirement entries, 67 independent required Dart
commands and zero architecture baseline entries. [roots.json](../tools/architecture/roots.json),
[roles.json](../tools/architecture/roles.json) and the
[feature inventory](001-feature-inventory.md) record the source scope and owners.

The final query/root disposition receipt records **zero confirmed or deferred
deletion leads within the finite reviewed inventory**. Zero-reference,
fixture-only, implicit-language, native/framework and retained owner-cycle leads
have concrete dispositions; test references alone do not establish shipping use.
The final `DashboardClient.apiDelete` wrapper-only subtraction is explicitly
reconciled against the predecessor query. The ambiguous `ChatRuntime.refuseOperation` is also retired; its two actual
callers now use explicit saved-edit and regeneration rejection commands. The
closed/owner/runtime/turn fence is preserved, and real semantic controls pass.
The real Administration DELETE branch
still uses `DashboardClient.apiDeleteResult`; its auth/session/401 behavior remains
owned by that active result path.

All 981 query visitor contexts have source-context dispositions, but their exact
node bindings remain uncertified. Context classification is not resolved-symbol
or universal runtime-liveness proof. The query belongs to the reviewed predecessor;
the final eight-line subtraction has an explicit successor binding, rather than
a claim that a new whole-query run occurred. Source review and finite candidate
closure do not establish that every possible runtime branch is reachable.

**Source/root/prevention closure is accepted (phase 7).** Current analysis,
production guards, composed 464-file host coverage, ordinary APK build,
product-mode instrumentation and pinned Chromium checks pass. Native source/root
review, nine guard/proof commands and 27 JVM controls bind the unchanged native
source; affected normal/enlarged light/dark renders were inspected. These gates
close the finite reviewed removals. Seven original phases are complete.

**Whole-program acceptance remains open:** phases 6 and 8 still require affected
installed-device journeys, matched phone performance and authorized latest-stock
runtime acceptance. Current source/host/build results do not certify those gates.

The hashes and counts in this inventory bind this cleanup audit snapshot.
Future responsibility/interface changes should update the relevant architecture
and role records; ordinary UI edits do not require global audit SHA-map changes.
The sections below retain historical candidate evidence, milestone counts and
then-pending obligations. The current disposition above supersedes their status
notes; the removal method remains guidance for future bounded closures.

The subsequent physical-phone probes add one explicit opt-in navigation root,
bringing the current authored census to 1,501 files. Production and retirement
counts remain unchanged. Its synthetic fixture is supported verification code;
it introduces no additional production deletion lead.

## Historical phase-0 scope and candidate basis

Phase 0 inventory, 3 October 2026. Scope is `/home/dev/projects/hermes-android/hermes-android`, base revision `a5650fa675209b6a782a5adf3f39ff12c53efb4c` plus intentional source/tool/document work. This is a complete **scope/root census and initial candidate map**, not a claim that every resolved member has already been proven live or deleted. The phase0 census below is historical. Phase2 DC01/DC02/DC04–07 deletion is now implemented, with source-bound resolved provenance in [dead_code/README.md](../tools/architecture/dead_code/README.md); behavioral verification is owned by the serialized root runner. The accepted program requires every remaining candidate to receive a final evidence-backed disposition; unresolved candidates block final completion.

The executable file census is [roots.json](../tools/architecture/roots.json): every tracked and intentional untracked file, every direct dependency, supported executable/dynamic roots and explicit platform/tool decisions. It excludes installed packages/node_modules, build/.dart_tool, Git and Python caches. Vendor/generated resources remain in scope as categorized inputs; they are not handwritten declaration candidates. At phase0, [roles.json](../tools/architecture/roles.json) classified 252 authored lib files / 251 real libraries and preliminary local traversal reached all 252: **zero whole-lib-file orphans**. Current roles/roots reflect subsequent removals and extractions. Member-level closure, conditional/alternate roots, native callbacks and test-only experiments still require separate proof. Tests importing a declaration do not establish a shipping use.

## Historical candidate closures

`proposed` means removal is evidence-supported for the stated closure and still requires the precise root/caller recheck and behavior gates during its deletion batch. `needs-decision` means absent normal references alone cannot justify deletion. Retained members/packages/resources are explicitly named to prevent over-broad deletion. Re-run the searches on the batch snapshot: concurrent migrations can change the closure.

| ID / declaration or artifact | Executable/dynamic roots and evidence | Deletion closure / current disposition | Acceptance after removal |
| --- | --- | --- | --- |
| DC01 `connection_manager.dart:948` ApiClient; :1158 GatewayChatClient; :1155 ToolProgressCallback | Source-bound resolution across 661 authored units confirmed closure; callers are ApiClient/GatewayChatClient groups in connection_manager_test and api_client_timeout_test. Active scoped paths use ProfileGateway, DashboardReadTransport and WsClient.send | **Removed (phase2); behavior gates pending root validation.** Delete inactive REST chat/session/SSE clients and exclusive tests/helpers/imports. `models/session.dart:2` Session becomes part of this closure (only ApiClient plus dedicated session_model_test). Keep ConnectionManager connection/secure credential storage and active stock transport | Active connection/setup/header/OAuth and profile gateway/outbox/history tests; remove obsolete tests rather than preserving their counts; no removed symbol/import left in authored scope |
| DC02 `ws_client.dart:646` sendStreaming through high-level session/chat/attachment/model wrappers (:690–1129) | Production ProfileGateway uses connect/waitForGatewayReady/send/events/close, not these wrappers. Dedicated old wrapper tests are sole external calls. No manifest/channel/alternate Dart roots invoke arbitrary Dart methods reflectively | **Removed member closure (phase2); active file retained, behavior gates pending root validation.** Removed wrapper APIs, test-only onGatewayReady/GatewayReadyCallback/isConnected, exclusive RemoteFileAttachment, stream listener maps/session stream bookkeeping and connection-closed listener machinery once references prove exclusive. Retain StreamEvent, StreamCallback/ConnectionCallback, JsonRpcError, auth/ready/correlation/send/close. **Retain** validReasoningEfforts/normalizeReasoningEffort/buildSessionModelValue (:1133 onward): controller and supported cross-client live tests use them | Authenticated handshake/RPC correlation/event delivery/reconnect/close/outbox tests and supported profile live fixture; search all removed symbols including tests/performance entry points |
| DC03 `attachment_draft_service.dart:34` AttachmentDraftMode.rest, :21 maxRestImageBytes, :349 validateRestDrafts, :36 allowsMultipleImageSelection | All production prepare calls select remoteGateway; REST validation/helper calls exist only dedicated test assertions. Remote aggregation limit and real image normalization still active | **Removed (phase2); behavior gates pending root validation.** REST mode/branches/limit/validation/helper and the dedicated REST test are deleted. All active callers/fake overrides use the single target API directly. Retain remote byte/pixel/staging cleanup and current upload behavior; no default flag/alias | Attachment draft/image parity/share/staging/failure cleanup tests; multi-image remote behavior and size/pixel limits survive; no REST-mode token remains |
| DC04 `gateway_insight.dart:52` GatewayInterimTransition | Source-bound resolved declarations/self plus dedicated gateway_insight_test group only; not used by current workspace transition owner | **Removed (phase2); behavior gates pending root validation.** Delete class/factory/exclusive group; keep active subagent/interim models and parsers | Active insight/workspace activity/subagent suites and symbol absence |
| DC05 `gateway_insight.dart:136` GatewayNotificationLevel / :138 GatewayNotification | Declaration/self plus dedicated parse test only; current notification delivery uses its own active models/owners/native sink | **Removed (phase2); behavior gates pending root validation.** Delete enum/class/parser/exclusive assertions; preserve notification delivery and subagent models | Notification/activity/insight tests and no removed reference |
| DC06 `gateway_activity.dart:220` GatewayTurnStatus | Declaration/self plus dedicated gateway_activity_test group only | **Removed (phase2); behavior gates pending root validation.** Delete class/parser/exclusive group; keep GatewayToolActivity and canonical live activity facts | Activity/tool/combined-state tests; no removed reference |
| DC07 `wing_theme.dart:47` WingStatus / :221 WingTokens.colorForStatus | Only wing_theme_test :91–95 calls mapper; production widgets select typed status token colors directly | **Removed (phase2); behavior gates pending root validation.** Delete unused enum/mapper/exclusive tests, keep all colors/tokens/contrast/theme and active status widgets | Studio theme/design/accessibility/status suites and no removed reference |
| DC08 direct `highlight` dependency (`pubspec.yaml`) | No package:highlight imports in lib/test/integration/tools; Flutter Markdown still uses its own dependencies. Direct-package inventory marks candidate-unused-direct | **Removed.** No direct pubspec or lock entry remains. Retained Markdown consumers remain; no replacement alias. Historical pre-removal package proof is preserved. | Offline package resolution/build/analyzer; retained Markdown/code block tests; package-owner inventory updates |
| DC09 `tools/fake_gateway/turn_recovery_contract.py:156` TurnRecoveryContractLedger (976-line experiment) | Imported/constructed only fake_gateway and its probes; advertises session.open/turn.reconcile/session snapshot capabilities absent inspected current stock; active client uses session.create/session.resume/prompt.submit | **Removed.** Fictional ledger file/dispatch/capabilities and exclusive probes are absent. Keep stock-shaped fake-gateway scenarios and deliberate disconnect injection; the fixture never defines the stock contract. | Independent stock-shaped handshake/session/prompt/history/events/disconnect tests; no fictional method advertised/dispatched; contract inventory pin refreshed before batch |
| DC10 `admin_providers_page.dart:26` final bool _busy = false in outer provider page | Outer page field is immutable false; inner credential/OAuth widget `_busy` fields (:353/:492) are real changing operation state | **Removed (phase2); behavior gates pending root validation.** Outer constant field and its two branches are deleted. Do not erase same-named nested busy fields or pretend this completes provider workflow migration | Provider screen interaction/loading/readback tests; inspect simplified enabled expressions; inner save/poll busy behavior retained |
| DC11 `assets/.gitkeep` and broad pubspec `assets/` declaration | Marker has no content/use; parent asset-directory registration may bundle only marker while individual assets have separate loaders/font/generator roots | **Removed.** Marker and broad parent registration are absent. Explicit privacy/pricing/portrait/font declarations and license/master-art/generator roots remain. Historical nonrecursive-folder proof is preserved. | Compare asset manifest/runtime loads and icon/font/pricing/privacy tests/build; no empty/redundant declaration or asset without root |
| DC12 official-desktop experiment tools: reproduce_official_regeneration_context.py, reproduce_official_attachment_boundary.py, audit_desktop_process_projection.cjs, generate_process_batch_fixture.py | Explicit CLI mains, source-path inputs and diagnostic/fixture generation purpose; not required PR jobs. Lack of app imports/CI does not prove these author tools are dead | **Retained supported executable roots.** Offline regeneration-context/attachment-boundary extraction, desktop process projection and process-batch fixture generation have concrete documented source-input/provenance purposes (see dead-code tooling README); absence of app imports/required CI is not dead-code evidence | Document retained invocation/purpose/current input requirement, or absence of deleted paths/callers and preserved live acceptance drivers |
| DC13 checked-in iOS scaffold/platform tree | AppDelegate @main, SceneDelegate/Info.plist registration, storyboard/project/asset catalog and RunnerTests are real framework roots | **Retained genuine framework roots.** Android-first is insufficient dead-code proof; AppDelegate/SceneDelegate, project/plists/storyboards/assets and native tests remain rooted. Dead-code cleanup does not authorize platform removal or certify feature parity | No dangling build/manifest/doc references; Android acceptance unchanged; release certification remains separate |

## Historical retention proofs and authored-area coverage

The file census includes every item in these areas; root entries explain executable/resource ownership. Counts below describe tracked base files; intentional architecture/plan/test additions are separately marked in `roots.json` and recounted as the work progresses.

| Area / base count | Reviewed root/declaration strategy and disposition |
| --- | --- |
| lib / 252 | Every file classified; all 134 views read in full; imported file reachability 252/252. Member candidates above require iterative resolved/caller closure. Shared values/helpers/parsers are not deleted merely because a branch looks simple |
| Android / 71 | 15 production Kotlin sources plus two native tests; main/debug/profile manifests, Gradle, channel/method registrations, Flutter plugin registration, native service/action/dismiss callbacks and renderer roots inspected. Density/API/night resources, shortcuts template/generated registration, notification layouts/keep.xml/provider paths, diagram runtime/vendor/licenses are dynamic/build roots |
| iOS / 39 | Swift entry/delegate, scenes/plist, storyboards/project/XCTest/asset/configuration framework roots inventoried; platform disposition remains DC13, not auto-delete |
| assets / 8 | Font/license/README, runtime icon, pricing JSON and artwork generator sources have roots. DC11 marker/parent registration is the only initial asset lead |
| test / 337 | Host test mains/independent behavior are roots. Separate exclusive obsolete declaration tests when removing DC01–07; never retain dead production code solely for its tests. New architecture/gate contracts appear intentional-untracked |
| integration_test / 54; test_driver / 1 | Actual Flutter/device/live mains inventoried individually; helpers/fixtures remain via their callers. Some files are reusable fixture helpers, not every .dart file is a root. Native/device/stock acceptance fixtures stay supported |
| scripts / 22 | CLI mains, CI/local wrappers, release and native drivers, diagram/icon/board generators and tests/lock/config inputs inventoried. scripts/diagram-preview/node_modules is installed output, excluded. release-history-start is consumed release boundary metadata |
| tools / 44 | Five alternate Dart performance mains and fixture/trace configuration, offline QA/phone/replay/native drivers, fake gateway/probes/requirements/docs included. DC09/DC12 distinguish obsolete protocol experiment from supported opt-in tools. New architecture/skill files are intentional authored tooling |
| .github / 9 | Six workflow/action definitions plus setup script/readme/license, funding/dependabot configuration. Jobs/scripts are dynamic CI roots, including newly wired offline QA/architecture gates |
| docs / 59; plans / 2 | References/history/policies are documentation inputs, not executable liveness proof. Update exclusive obsolete API/fixture instructions with deletions; preserve useful history unless its purpose is obsolete. New program/verification/inventory/review documents are intentional |
| fastlane / 4 | Store title/descriptions/icon metadata, no Fastfile/Appfile; retain supported publication inputs |
| Root files/manifests / 15 | AGENTS/CONTEXT/CONTRIBUTING/readme/security/privacy/licensing/release history/config, pubspec and lock/build inputs explicitly scoped. Direct package owner table is in roots.json; all direct declarations classified, including analyzer and yaml new tooling consumers |

Specific non-deletions: `ic_stat_connection.xml` is consumed by `scripts/generate-notification-board.py:60`, even though it is not an active Kotlin notification icon. The supported notification board source root keeps it until that generator/design artifact is retired. MainActivity string channel callbacks, retained MonitoringRuntime engine, FileProvider authority/file_paths, plugin `ic_stat_wing` keep rule, native diagram assets and Gradle-generated launcher shortcuts have dynamic roots. Performance alternate mains/QA defines and fixture injection are supported behavior, not unreachable shipping code. Licenses/resource masters and metadata may be source/build/publication roots without an application import.

## Executable removal method and proof obligations

Run from the application checkout. These are inspection/removal procedures, not executed deletion claims:

```sh
git ls-files -z
git ls-files --others --exclude-standard -z
rg --files lib test integration_test test_driver tools scripts android ios assets .github fastlane
rg -n '^(import|export|part|part of)' lib --glob '*.dart'
rg -n '<(activity|service|receiver|provider)|android:name|tools:keep' android --glob '*.xml'
rg -n 'MethodChannel|EventChannel|setMethodCallHandler|registerViewFactory|GeneratedPluginRegistrant|@main|NSClassFromString|Class.forName|getIdentifier' lib android ios --glob '!*.min.js'
rg -n 'flutter .* -t|flutter test|python3? |node |dart |scripts/|tools/' .github scripts docs tools --glob '!*.min.js' --glob '!roots.json'
```

For each member candidate, enumerate declaring library/class, all resolved references/callers (including tear-offs, aliases, cascades/extensions and exports), tests and supported alternate roots. Follow native string/reflection/manifest registrations and package/plugin/asset loader/build inputs separately. Use parsed graph for file dependencies; a raw grep cannot prove arbitrary Dart member reachability. If resolution is ambiguous, record the exact ambiguity and do not delete the member speculatively. Update the candidate with the executable symbol query/tool version/scope/output, caller and dynamic-root evidence.

Compute the smallest complete deletion closure: declarations → exclusive helpers/imports/exports/branches/fields → exclusive tests/fixtures/tool/docs → package/resource/platform/build entries. If any helper has a supported caller, retain it; DC02's then-retained reasoning helpers are a historical example. Remove actual files/members; renaming, moving into an archive or leaving compatibility wrappers is not removal. After deletion, regenerate role/root/package inventories and candidate scan to reveal secondary orphans. Analyze and run the focused behavior gates first, then required broader checks. A failing test around a removed obsolete method should be removed with that obsolete contract, while shipping behavior tests remain.

Every candidate gets one final status: removed (closure/evidence/gates), retained (named supported executable/dynamic consumer), or unresolved (specific decision/proof blocker). The program cannot close with unresolved candidates, omitted authored areas, stale roots/roles/baselines, or a negative search presented as complete liveness proof. Framework/vendor/generated roots must be reviewed deliberately; excluding them from handwritten declaration scans does not exclude their assets/configuration/support obligations.

## Historical phase 0 evidence and remaining work

Executed read-only evidence: Git tracked/untracked census; full role/library inventory; native registrations/manifests/resource/Gradle and script/CI/package loader scans; complete 134-view content review; active production vs tests/alternate callers for DC01–10; preliminary whole-file graph reaches 252 files. The architecture agent ran no tests/builds/devices and edited only its five inventory/document files. Root owns independent baselines and implementation checks.

**Remaining work is explicit:** exhaustive resolved-member scan/removal and secondary orphan iteration across all authored areas; DC08 manifest resolution and DC11 final resource acceptance; continued supported DC12 tool/DC13 framework-root accounting; full deletion batches/guards/behavior/native/stock/phone acceptance from the verification plan. Initial candidates are evidence-backed leads, not the total final dead-code set. The scope census prevents untracked/tool/native/resource areas being forgotten; the member/root proof prevents unsafe deletion.

## Historical ongoing pilot cleanup

The dormant library-private `AdministrationContent._accessChecks` registry and
its exclusive construction, gateway update, health forwarding and disposal paths
are removed. Full caller review found ordinary Administration only created and
updated these controllers; it neither started their checks nor displayed their
results. The Health route already used the retained
`AdministrationHealthSession.checksFor` owner, which is preserved. The successor
passes 82 owner/route/navigation checks, including ordinary Administration not
starting Health work, and joined Flutter analysis reports no issues. Exact before
and after sources are bound by the private diagnostics snapshots. This is one
member/state closure; complete authored-member and dynamic-root closure remains
pending. The existing completed-view prevention rule is being extended for the
related direct diagnostic-mutation pattern.

Scheduled-task raw public preferences access was removed after production routes switched to explicit owner factories and child-route leases. Controller tests now retain their injected preferences directly. The exact retired member is guarded independently by invalid/valid declaration fixtures; it must not return as a getter or compatibility wrapper. The obsolete MainActivity `openInputStream` substring test was removed: its assertion described the replaced implementation and did not prove intake correctness. Manifest intent declarations remain tested; cancellable transfer guards, fresh JVM tests and the controlled stalled-provider device journey own the new transfer contract. Final paired host/native/renderer acceptance remains pending.

## Historical ordinary Administration owner cleanup

The ordinary Administration parent no longer retains a second `AdministrationHealth`
cache. Its overview/task observation publishers had no ordinary-screen consumer;
the dedicated Health route keeps its existing retained owner. One parent-owned
`ProfileOverviewSession` now serves the header, search and body. Its child receives
that session instead of constructing a second lifetime or publishing observations
back through callbacks.

This closure removes 17 declaration surfaces across three libraries: the unused
cache, revision/key policy, publisher methods and callback/factory interface,
plus the obsolete completion generation. Direct production and test callers have
been switched; no whole files were removed. Exact original and successor sources
are preserved privately. The existing retired-declaration guard now lists these
identities; nine focused invalid/valid fixtures cover representative fields,
getters, methods and legitimate borrowed ownership. Independent source review
found no material issue. All 62 guard fixtures and the three CLI exits pass;
the repaired production scope reports zero retired declarations. The captured
editor-return regression reproduces the wrong-profile read on original source
and passes the successor. Broader feature disposition remains pending. This is an implemented deletion awaiting acceptance,
not whole-Administration or whole-checkout dead-code closure. Health/runtime
coordination and the final resolved-member/root sweep remain explicit obligations.

## Historical census freshness during migration

The file-set census has been refreshed from the current tracked and intentional
untracked checkout. `ARCH_AUTHORED_CENSUS` now independently rejects missing,
stale and duplicate file entries, with actual invalid/valid/input-error CLI
fixtures discovered by offline QA. Both quality workflows invoke its production
command; the mandatory-gate checker prevents omission or swallowed failures.
Its [contract](../tools/architecture/rules/authored_census.md) records fixed
exclusions, Git-ignore limitations and the feedback budget. Independent review
added regular files with cache-directory names, strict schema/NUL input handling,
whitespace checkout paths and real commit/linked-worktree acceptance.

This closes stale **file scope** as a silently missed pattern. The existing
executable/dynamic-root entries and direct-dependency consumers still require
fresh semantic/registration proof after the ongoing extractions. A matching
census does not establish complete roots or declaration liveness. Full member
closure and zero unresolved candidates remain pending. Exact census/hash/CLI
proof and the original stale-manifest failure are private ignored evidence.

## Historical connection auth reader closure

The former model-owned `DashboardOAuthSession` library/export is retired, with no forwarding wrapper; the runtime owner is retained under services and immutable `DashboardOAuthGrant` becomes the domain value. Public `SavedConnection.fromMap` remains supported for current credential-free metadata. Its plaintext credential reader branches and false migration comment are removed: the manager already rejects those inputs before parsing. The opt-in approval integration fixture is an explicit private-input consumer and now separates its current credentials from metadata. Historical tests describing plaintext compatibility are replaced with current metadata round-trip/rejection behavior. This is a reviewed branch closure, not a claim that the whole metadata constructor is dead. Corrected constructor resolution and input-schema evidence are required; zero matches from the earlier misqualified constructor query are not proof. Exact secure/portable field schemas remain supported, as specified by the [auth contract](001-connection-auth-ownership-contract.md).


## Historical accepted composer and operation API subtraction

The accepted frozen composer/operation batch removes 22 former `ProfileChat`
work surfaces and 28 operation/health/view API identities. Mutable composer work
now belongs to `ComposerSession`; operation polling belongs to
`AdministrationOperationSession`, and route-bounded durable Doctor draft retry
belongs to `DoctorFindingDraftSession`. Moved values are active under their new
domain libraries; retirement is qualified by the former declaring library.
No compatibility forwarding properties or parallel polling/cache were retained.

The exact added identities are grouped below. All are protected by the existing
`ARCH_RETIRED_DECLARATION` manifest, which contains 155 total entries on this
accepted source. This proves finite declaration absence, not arbitrary liveness
or renamed duplicate policy.

| Former declaring library | Removed exact identities |
| --- | --- |
| `lib/core/services/profile_workspace_controller.dart` | `ProfileChat.draft`, `ProfileChat.draftSubmissionUncertain`, `ProfileChat._outgoingPrompt`, `ProfileChat.attachments`, `ProfileChat.queuedPrompts`, `ProfileChat.editingQueuedPrompt`, `ProfileChat.queuedEditText`, `ProfileChat.composerText`, `ProfileChat.queuePaused`, `ProfileChat.steering`, `ProfileChat.draftRestored`, `ProfileChat.queueMutating`, `ProfileChat.queueDraftChanged`, `ProfileChat.queueDraining`, `ProfileChat._attachmentPreparations`, `ProfileChat._imagePreparationGeneration`, `ProfileChat._imageJobs`, `ProfileChat.preparingAttachments`, `ProfileChat._submissionInFlight`, `ProfileChat.sendingPrompt`, `ProfileChat._draftWrites`, `ProfileChat._draftRevision` |
| `lib/core/services/administration_repository.dart` | `AdministrationAction` |
| `lib/core/services/administration_health.dart` | `AdminDiagnosticObservation`, `AdministrationHealth.beginDiagnostic`, `AdministrationHealth.observeDiagnostic`, `AdministrationHealth.trackDiagnostic`, `AdministrationHealth.finishDiagnostic`, `AdministrationHealth.diagnosticGeneration`, `AdministrationHealth.beginServerRefresh`, `AdministrationHealth.recordDiagnosticAttempt`, `AdministrationHealth._diagnostics`, `AdministrationHealth._diagnosticTimers`, `AdministrationHealth._pendingScopes`, `AdministrationHealth._refreshDiagnostic` |
| `lib/core/screens/administration/admin_operations_page.dart` | `startAdminOperation`, `AdminActionPage.server`, `AdminActionPage.action`, `AdminActionPage.onObservation`, `AdminActionPage.initialObservation`, `AdminActionPage.chatController`, `_AdminActionPageState._status`, `_AdminActionPageState._timer`, `_AdminActionPageState._check`, `_AdminActionPageState._preparedChat`, `_AdminActionPageState._preparedPrompt`, `_AdminActionPageState._openingFinding` |
| `lib/core/screens/administration/admin_runtime_health.dart` | `_startDiagnostic`, `runAllHealthDiagnostics`, `refreshHealthDiagnostics` |

The source manifest SHA-256 is
`cf62e41fc3811693afb95e4123d75fb04d6be734dfec0873b9ff1a4e64a4d3e0`,
binding 1280 authored paths and the accepted 320-production-file / 312-library
scope. Source analysis reports no issues; 11 architecture rules report zero
blocking findings and three existing baseline entries. The 150 distinct affected
passing checks are linked across the preserved predecessor and targeted repairs,
including original held-steer ABA RED / successor GREEN and transient/persistent
ACK cleanup. The full suite was not repeated after the limited repairs.

Workspace runtime/transcript, reading, browser/lifetime, voice/share-review and
remaining administration/log policies are still explicit obligations. The two
later unwired tool owners, preview guard drafts, exhaustive secondary orphan and
authored-member/dynamic-root closure, and final host/native/device acceptance
are outside this batch. Historical candidate rows above retain their original
evidence/dispositions; these removals do not declare the whole program complete.

## Historical tool setup deletion and typed reading handoff

`AdminToolSetupList` was deleted after an accepted-scope resolved caller query:
888 authored Dart units, four references internal to its own declaration,
zero external callers, unresolved spellings or resolution errors. Authored
non-Dart roots contained no registration. The existing voice view moved to
`admin_voice_page.dart`; it remains active and is not a dead-code deletion.

The obsolete setup/model fields and methods and raw tool-leaf `messages` input
are absent from the reviewed successor. Their finite retirement guard handoff passed focused verification:
23 added identities,178 total entries. ProfileMessage retains its legitimate `message` name with a
required typed value; a separate small input-type guard protects that boundary.
The paired source passed 144 affected checks and full analysis with no issues.
Whole-member, dynamic-root and final authored dead-code closure remain pending.

## Historical unadopted tooling subtraction

Nine unregistered draft/orphan files (2533 lines) were removed after complete
current-authored reference and root review: the composer preview/file-resource
and selection-key guard bundles (rules/contracts/fixtures/host wrappers), plus
`docs/ADMINISTRATION_OPERATIONS.md`. Their only executable callers were inside
their own bundles; no CI/aggregate/README/executable root or direct dependency
required them. The duplicate operation document's useful clarifications were
merged into the canonical operation contract. Original bytes/hashes and exact
reference/deletion dispositions are retained privately.

Keep `semantic_context.dart` (three accepted guard callers), `dart_sdk.dart`,
accepted codec/view-I/O guards, actual attachment dimension/read-retirement
regressions and preference persistence/ordering/repair guards. The preview draft
constructor counterexample was newly invented; precise static prevention of
adapter-file Image.file/FileImage calls is not claimed. The selection-key draft
could not protect raw/computed keys or persistence ordering; original raw-store
removal, one private writer and retained behavior regressions remain.

This is finite subtraction; whole-checkout member/dynamic-root closure is pending.

## Historical skills and history-search responsibility closure

Skills view-owned parsing/provenance/edit-baseline/command outcomes now belong to
`ProfileSkillsSession`; Find collection/paging/retry/dedup/query projection belongs
to `ChatReadingSession`. The existing retirement guard adds39 exact identities
(19 Skills,19 Find and the rejected per-chat temporary `_readingWindow`),217 total.
No forwarding alias preserves the old APIs. One controller-owned active temporary
window remains valid; releasing old focus cannot clear a newer selection.

The frozen1308 successor passed clean analysis,66 affected host checks, production
namespace guards, required CI and authored census; all1308 hashes stayed unchanged.
Each new dependency guard rejects the original raw-adapter view import. The
A/B/A window test preserves current navigation/identity behavior rather than
claiming an original functional RED or measured capacity. Exact retirement and
namespace checks cannot detect every renamed policy. Whole authored-member,
dynamic-root and later source/native/device closure remains pending.

## Historical connector, output and Logs responsibility closure

Captured owners replace view-owned connector provisioning/readback, output
discovery/preview/delivery policy and log query/parsing/lifetime. Forty exact
removed identities (19 connectors/setup,16 Outputs,5 Logs) bring the retirement
manifest to257. Actual original-source checks detect each removed identity.
Moved plugin policy remains live and mixed; temporary-file lifecycle and whole
member/dynamic-root inventories remain obligations.

Six independent commands reject the original incorrect dependency/value/mount
patterns and are mandatory in both CI workflows. The borrowed detail initial
refresh produced an actual mounted-list build error; captured post-frame refresh
passed the same route and both-theme render checks. Immutable download tests
cover producer/consumer mutation. Finite syntax/dependency guards do not establish
arbitrary asynchronous safety or all renamed business policy.

## Historical canonical transcript ownership closure

`TranscriptReading` replaces21 mutable `ProfileChat` APIs; the retirement guard
now protects278 identities. Snapshot admission copies external values; fixed-field
capture shares only owned immutable content and carries no runtime authority.
Attachment-type and capture semantics use public behavioral controls, while
existing role and retirement guards prevent the old ownership structure. Focused
acceptance covers221 checks; grouping/runtime and full member/root closure remain
open.

## Historical voice and plugin responsibility closure

Existing voice owners replace27 view/controller public mutable surfaces; the
plugin owner replaces3 view-owned identities. The retirement guard protects308
identities. Three independent dependency commands reject original raw-adapter
imports and are mandatory in both CI workflows. Behavioral controls retain
admitted autosave durability, saved-profile-only preview and plugin ACK/readback
uncertainty without replay. Moved voice value types remain live in their domain
module. Whole member/dynamic-root closure and plugin visual inspection remain open.

## Historical pure timeline responsibility closure

Grouping, nearby selection, reasoning and answer-action projection moved out of
widgets to immutable timeline facts. Seven superseded declarations are protected
by the existing retirement guard (315 total); the existing typed reading-input
rule also protects the two canonical timeline inputs. Production analysis and
125 focused controls pass. This is ownership closure, not final renderer, runtime
or whole-checkout dead-member acceptance.

## Historical workspace entry and usage responsibility closure

The captured entry owner replaces four shell declarations; the usage owner and
immutable cost facts replace fifteen view/raw-map declarations. All nineteen are
protected by the existing retirement guard (334 total). Independent key-owner
and usage-dependency rules bring the Dart command count to47; the existing raw
preferences rule now also checks the canonical Home state. Analysis and focused
owner/caller controls pass. Whole-checkout member/resource/dynamic-root deletion
and the remaining bootstrap preferences baseline still require final closure.

## Historical runtime and small policy subtraction

The runtime/secure/clarification/header closure removes48 exact declaration
identities, bringing the retirement manifest to382. The actual original source
produces48 retirement violations; successor source produces none. Runtime facts
now belong to ChatRuntime; no old ProfileChat forwarding getters remain.

AdminLoad and its private state had no production caller or dynamic registration.
Both classes and exclusive imports are removed. Three loader-only test cases
were removed with that obsolete contract. The retained ReadRecovery lifecycle
and network controls remain; the narrow/enlarged error-scroll fixture now uses
the shipping AdminNotice directly. This is a bounded deletion closure, not a
complete member/resource/dependency liveness claim. Whole-checkout closure and
secondary orphan iteration remain phase7 obligations.

Shared-draft ownership removes26 further UI declarations; total408 are protected
by exact retirement identities. All26 actual original declarations fail the
retirement gate; current source has none. The destination review no longer
imports four raw workflow namespaces, enforced by its small mandatory linter.
The registry remains the sole controller disposer in review fixtures; duplicate
fixture teardown callbacks were removed while every shipping assertion remains.

Provider recovery removes23 further raw view/workflow declarations;431 exact
identities are now protected. All23 actual original declarations fail the
retirement gate. The mandatory provider view guard rejects the original raw
administration adapter and permits the typed owner. Existing library-cycle
checking protects the route composition seam. No backwards compatibility alias
or old/new recovery view path is retained.

Slash completion removes5 further raw view/duplicated result declarations;436
exact identities are protected. All5 actual originals fail the retirement guard.
A small mandatory dependency guard prevents the suggestions library from
reacquiring the raw workspace controller namespace. Existing behavior assertions
and one Unicode/query immutable-observation control are retained.

Notification ownership removes26 raw application/channel/chat declarations and
moves NotificationInput to its domain library without an alias;463 exact retired
identities are protected. All27 actual original declarations fail the gate.
Private channel/focus storage and existing analyzer rules protect direct writes;
cycle checking prevents domain facts from living in their dependent coordinator.

Resource ownership removes18 exact view-loading/state/old-adapter declarations,
bringing protected identities to481. The original source scan finds all18 plus
three older notification fields from that original base. No claim is made that
this bounded retirement scan proves complete whole-checkout dead-code removal.

Phase7 bounded subtraction: remove TurnNotificationService's instance workflow
(nine identities including constructor), GatewaySubagentActivity.isComplete and
JsonRpcError.safeToResubmit. Actual resolver evidence:995 authored units parsed,
166 candidates resolved,61 references, no unresolved target/inheritance/errors;
15 production references were internal to the removed workflow and46 were host
fixtures. Native/tools had zero target callers. Preserve static notification
channels/ID helper, active plugin adapter/port, event/history isComplete facts,
error data/reason parsing and no-replay behavior. Only exclusive obsolete tests
are removed; the two static ID assertions and merged activity assertion remain.
The existing retirement guard now handles constructor declarations and492 exact
identities. This does not certify the remaining whole-code/asset/dependency closure.

Supervision removes35 exact raw panel inputs, polling helpers and mutable
workflow fields;527 identities are protected. The actual original three views
fail both namespace and exact-retirement scans. Required control-admission
parameters and standard analysis protect missing caller closure.

Workspace voice removes six exact obsolete UI/admission declarations;533 exact
identities are protected. The public-owner-state rule covers seven actual private
recorder/playback facts, and the last main raw-storage baseline is removed.
Whole member/branch/file/resource/dependency subtraction remains open.

Browser/project retires46 exact obsolete view/helper/wire declarations. The
protected manifest now contains579 identities;59 independent commands are wired
to both quality workflows. This bounded source/host acceptance does not close the
whole public-member/branch/file/native-dynamic root review.

## Historical file/resource/dependency root reconciliation

The accepted subtraction source has 1,422 authored paths. Every one of its
612 pre-existing executable/resource root paths exists. This reconciliation
adds the real Android generated-plugin-loader root and resolves four stale
DC12 needs-decision rows to their supported CLI purposes and exact source-input
prerequisites. The five iOS reference rows retain genuine framework/build/test
inputs without claiming iOS product acceptance; they are not unresolved removal
decisions.

DC08, DC09 and DC11 are removed as reflected above. The historical
dependency_asset_proof.json remains unchanged. Current pubspec has 25 direct
packages: yaml and path are runtime dependencies of ProfileIdentityRepository;
analyzer remains tooling-only and flutter_lints is read by analysis_options.yaml.
The root-table consumer lists now describe current source import/export headers,
including part files and conditional directive strings. This directive inventory
does not claim resolved namespaces or member liveness.

All seven asset files retain actual runtime, license or generator purposes.
Android manifest/channel/intent/platform-view and density/API/night/theme/provider
resources, diagram renderer allowlist and licensing, generated Flutter plugin
registration, iOS storyboards/assets/XCTest, Fastlane store metadata and release
boundary inputs remain rooted. ic_stat_connection.xml belongs to the documented
notification-board generator. Direct app-package absence does not justify removal
of JNI/transitive plugins, Playwright's pinned renderer tool dependency, local
sharp, FontTools/Lucide sources or official-checkout esbuild/TypeScript inputs.

No additional source/tool/asset/package deletion is proven by this reconciliation.
Remaining evidence obligations are final coherent post-migration resolved
member/branch/constructor closure (especially public APIs used only by fixtures),
native lifecycle/reflection/variant closure beyond the registered roots, secondary
orphan recheck after pending ownership integrations, and fixed-source
host/build/native/resource acceptance. Whole-checkout dead-code completion is
not claimed.

Canonical workspace authority removes the public commandCatalog, retry and
reconnectFuture implementation surfaces; their private implementations remain
owned by the coordinator. The other75 original fact surfaces become readonly
getters, rather than retired behavior. The retirement manifest protects582 exact
identities. Whole-declaration/branch/root closure remains open.
