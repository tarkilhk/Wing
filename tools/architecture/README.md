# Architecture guards

These independent guards protect the architecture established by the completed
cleanup. The aggregate runner shares a parsed input snapshot for its registered
rules; additional commands below protect their own scopes. No rule changes
source, manifests or the empty migration baseline. Use
[maintain-feature-architecture](../agent_skills/maintain-feature-architecture/SKILL.md)
to maintain ownership records alongside feature changes.

The tracked pre-commit hook invokes `scripts/check_commit_linters.py --staged`.
It checks the exact staged tree with the existing rules and leaves source and the
index untouched. See [local commit checks](../../CONTRIBUTING.md#local-commit-checks)
for installation. Quality CI runs on all branch pushes; `REQUIRED_QUALITY_GATE`
also protects that trigger from branch/path filtering.

From the application checkout:

```sh
dart run tools/architecture/check_all.dart
flutter test --no-pub test/architecture_contract_test.dart
```

Resolved guards share the source/SDK/configuration-bound summary helper in
`semantic_context.dart`, including completed model/setup views, identity
presentation and backup ownership. Cache entries retain the pinned analyzer's
summary keys, reader and
checksum/version validation; rule verdicts are recomputed. Atomic writes finish
before `putGet` returns, so disposal and immediate fixture deletion cannot race
queued cache writes. `test/workspace_entry_key_owner_guard_test.dart` checks that
completion boundary and runs the real ownership fixture/CLI cleanup path. The
existing semantic fixture suites still exercise source/dependency mutations,
corrupt bytes, imports, aliases and source/AOT exits. This is a behavioral
lifetime property, not a pattern that a source linter can establish.

In complete host runs, production guards inspecting the same checkout share
one summary namespace with the same root/SDK/options/package binding. Fixture
roots keep their separate namespaces. Neither mode shares previous findings.

Source enforcement stays on every local commit (with the hook installed),
branch push/PR and release. Exhaustive checker self-tests run nightly, when
checker/runner/fixture/dependency inputs change, and before a published release. Routine
`python3 scripts/test.py` includes all current-source linters and product tests;
`python3 scripts/test.py --full` includes every original checker proof too.
The selected/scheduled inventory is explicit in `tools/testing/test_batches.dart`;
unknown new suites remain routine. Choose local checks and retries using
[verification scope and stopping](../../docs/TESTING.md#verification-scope-and-stopping);
see [verification cadence](../../docs/TESTING.md#continuous-checks) for CI.

The one-process linter driver also enters `model.withSharedSourceParses`.
Only valid parsed trees are reused for the same canonical root, absolute file
path and exact current source text. Every rule rereads the files and role
manifest and rebuilds source wrappers, dependencies, part ownership, libraries,
graphs and findings. The cache retains only the current root's present files
and ends with its batch. Consumers treat parsed ASTs as read-only.
`test/architecture_source_parsing_test.dart` protects same-size/same-mtime
mutations, syntax repair, manifest-only edits, file/part changes and scope/root
isolation.

The journal ACK and identity presentation proofs replace authored fixture
sources within one suite-owned directory. They retain dependency summaries
between cases, recreate the analyzer context for every check, and rewrite roles
and package configuration for the current fixture. Previous fixture sources are
removed before the next case, including identity file-URI helpers outside `lib`.
The suites still execute their actual source CLI and SDK controls; their
positive, negative and malformed-input cases also check that reused summaries
cannot preserve a previous verdict. The journal supervisor removes its entire
scratch directory after the child exits, and identity cleanup runs in `finally`.

The complete host runner compiles architecture commands together from the
current checkout once per run into a native AOT snapshot, then launches each
selected original `main` in a fresh `dartaotruntime` process. The runtime comes
from the selected SDK, preserving implicit running-SDK discovery. Fixture
compiler and analyzer commands use that SDK's actual `dart` executable. `proof_process.dart` forwards inner CLI commands to that same
run-owned artifact; fresh arguments, roles, fixture files and diagnostics are
still checked on every invocation. Native compilation/execution and SDK analyzer
commands stay independent. The command manifest includes all discovered guard,
fixture and dead-code mains; compilation and unknown-command errors fail the run.
Journal and colours supervisors route their streamed children through the same
artifact, retaining inherited environment, suite-owned `TMPDIR`, child flags
and exit codes. They drain streams and await child exit before deleting scratch
roots. Reviewed host wrappers share dedicated batches, preserving each original
main and test callback while amortizing Flutter and analyzer startup. The
runner's temporary artifacts are deleted only after its children finish.

Standalone proofs use `proof_process.dart` to scope CLI compilation and child
lifetimes. The first three source launches run unchanged. Repeated invocations
then compile that current guard once to a temporary kernel and execute it in a
fresh Dart process for each fixture. Any newly observed exit status also runs
the source command, checks source/kernel exit agreement, and returns the source
result to the original diagnostic assertions. Argument and workflow data are
read on every invocation; no fixture verdict or cross-run artifact is cached.
Native AOT compilation/execution and actual SDK analyzer controls stay direct
subprocesses. The scope waits for its children before deleting its artifacts.
`test/architecture_proof_process_test.dart` checks input forwarding, source exit
controls, compile/exit failures and artifact cleanup.

The profile-colours proof likewise replaces its ordinary fixture sources within
one directory. Its ten cache transitions and separate corrupt-summary controls
keep their independent workspaces and all source/dependency/options/SDK checks.

`test/required_quality_gates_test.dart` compiles the current gate command to a
suite-owned kernel once, then executes its real `main` in a fresh Dart process
for every workflow mutation. It retains the independent source-launch rejection
and repair controls. Every invocation still validates the current YAML, exit
status and diagnostics; no workflow verdict or cross-run executable is cached.

Multi-CLI fixture timeouts are subprocess watchdogs, separate from the rules'
recorded quiet-host performance budgets. The saved-prompt admission wrapper uses
the same two-minute watchdog as other multi-CLI fixtures for its three fresh
source processes; it retains every diagnostic and 0/1/2 exit assertion. When
compiler subprocesses compete for CPU, use `flutter test --concurrency=2` for a
bounded host integration run; this changes scheduling, never assertion coverage.

Each rule also has its own command:

```sh
dart run tools/architecture/rules/capabilities_view_dependencies.dart
dart run tools/architecture/rules/tool_setup_view_dependencies.dart
dart run tools/architecture/rules/reading_view_inputs.dart
dart run tools/architecture/rules/skills_view_dependencies.dart
dart run tools/architecture/rules/find_view_dependencies.dart
dart run tools/architecture/rules/connectors_view_dependencies.dart
dart run tools/architecture/rules/mcp_setup_view_dependencies.dart
dart run tools/architecture/rules/outputs_view_dependencies.dart
dart run tools/architecture/rules/download_file_value.dart
dart run tools/architecture/rules/logs_view_dependencies.dart
dart run tools/architecture/rules/connector_detail_mount.dart
dart run tools/architecture/rules/voice_view_dependencies.dart
dart run tools/architecture/rules/speech_synthesis_view_dependencies.dart
dart run tools/architecture/rules/plugins_view_dependencies.dart
dart run tools/architecture/rules/workspace_entry_key_owner.dart
dart run tools/architecture/rules/usage_view_dependencies.dart
dart run tools/architecture/rules/chat_runtime_observation.dart
dart run tools/architecture/rules/secure_reply_view_wire.dart
dart run tools/architecture/rules/shared_draft_view_dependencies.dart
dart run tools/architecture/rules/provider_recovery_view_dependencies.dart
dart run tools/architecture/rules/slash_completion_view_dependencies.dart
dart run tools/architecture/rules/resource_preview_view_dependencies.dart
dart run tools/architecture/rules/supervision_view_dependencies.dart
dart run tools/architecture/rules/workspace_voice_view_dependencies.dart
dart run tools/architecture/rules/browser_view_dependencies.dart
dart run tools/architecture/rules/project_actions_view_dependencies.dart
dart run tools/architecture/rules/row_actions_view_dependencies.dart
dart run tools/architecture/rules/browser_values.dart
dart run tools/architecture/rules/workspace_canonical_state.dart
dart run tools/architecture/rules/workspace_search_owner.dart
dart run tools/architecture/rules/transcript_history_dispatch.dart
dart run tools/architecture/rules/profile_discovery_writer.dart
dart run tools/architecture/rules/saved_prompt_journal_admission.dart
dart run tools/architecture/rules/retired_answer_versions_namespace.dart
dart run tools/architecture/rules/resume_durable_identity.dart
dart run tools/architecture/rules/intelligence_read_admission.dart
dart run tools/architecture/rules/domain_dependencies.dart
dart run tools/architecture/rules/business_view_dependencies.dart
dart run tools/architecture/rules/business_rendering_types.dart
dart run tools/architecture/rules/library_cycles.dart
dart run tools/architecture/rules/role_inventory.dart
dart run tools/architecture/rules/view_lowlevel_dependencies.dart
dart run tools/architecture/rules/view_draft_write.dart
dart run tools/architecture/rules/image_codec_confinement.dart
dart run tools/architecture/rules/image_codec_provenance.dart
dart run tools/architecture/rules/completed_model_view.dart
dart run tools/architecture/rules/public_owner_state.dart
dart run tools/architecture/rules/task_view_protocol.dart
dart run tools/architecture/rules/settings_view_protocol.dart
dart run tools/architecture/rules/owned_model_mutation.dart
dart run tools/architecture/rules/overview_view_wire.dart
dart run tools/architecture/rules/provider_view_protocol.dart
dart run tools/architecture/rules/memory_view_protocol.dart
dart run tools/architecture/rules/deleted_draft_cleanup_boundary.dart
dart run tools/architecture/dead_code/retired_declarations.dart
dart run tools/architecture/rules/model_catalog_fixture.dart
dart run tools/architecture/rules/dart_main_roots.dart
dart run tools/architecture/rules/completed_setup_view.dart
dart run tools/architecture/rules/app_preferences_view.dart
dart run tools/architecture/rules/visibility_key_owner.dart
dart run tools/architecture/rules/backup_owner_boundary.dart
dart run tools/architecture/rules/app_preferences_construction.dart
dart run tools/architecture/rules/profiles_management_view.dart
dart run tools/architecture/rules/profile_identity_view.dart
dart run tools/architecture/rules/profile_colours_view.dart
dart run tools/architecture/rules/browser_row_work.dart
dart run tools/architecture/rules/notification_journal_ack.dart
python3 tools/architecture/rules/authored_census.py
python3 tools/architecture/rules/native_retired_resources.py
python3 tools/architecture/rules/fixture_model_catalog.py
python3 tools/architecture/rules/retired_fixture_recovery.py
python3 tools/architecture/rules/stock_task_blueprint_schema.py --input response.json
python3 tools/architecture/rules/stock_task_blueprint_slots.py --input submissions.json
python3 tools/architecture/rules/stock_task_schedule_projection.py --input observations.json
```

The separate YAML guard `rules/required_quality_gates.dart` has its own command
and fixtures. It does not need a Dart graph or a migration exemption. CI invokes
`python3 scripts/check_commit_linters.py --dart-only` to run the aggregate and
every independently owned Dart source check in one VM, sharing source parses
and analysis summaries. A standalone rule is excluded only when the aggregate
registers and executes it. New independent rules are discovered automatically;
unsupported entry points fail verification. PRs pass the preceding baseline
with `--baseline-reference` to the aggregate alone. Python runner proofs cover
discovery, argument handling and failure propagation in both workflows.

The YAML guard rejects omitted, fixture-only, conditional or softened source
steps, and requires the consolidated Dart gate before PR host tests that use
`--skip-linters`. Python census, retired-resource and fixture-catalog source
checks remain explicit in both workflows. Native source checks run after Gradle
setup supplies compiler dependencies; their separate fixture proofs remain
mandatory. The authored-census guard protects file-set coverage rather than
declaration liveness. Standalone Dart commands remain useful for focused checks;
running the graph aggregate alone does not establish independent rule contracts.
The independent Dart catalog-fixture guard is enforced through the ordinary host
suite, including a full authored fixture scan and actual CLI exit proofs.
The independent completed-model-view guard runs through its mandatory host
wrapper. Its precise scope and feedback budgets are documented in
`rules/completed_model_view.md`. The native provider and queue guards have
separate commands and mandatory CI fixture proofs in `native_share/README.md`.
The independent settings-view guard runs through its mandatory host wrapper;
`rules/settings_view_protocol.md` records its resolved provenance and budgets.
The stock schedule projection guard checks exported actual fixture create/update
responses in `scheduled_tasks_schedule_projection_test.dart`; offline Python
fixtures prove its invalid/valid/input-error exits. Native voice file guards and
their mandatory CI fixture proofs are described in `native_voice/README.md`.

The independent owned-write, overview, provider, memory and deleted-draft cleanup
guards have their own host wrappers and rule contracts. Their production scans
and fixture proof commands run in the mandatory full host suite; passing the
graph aggregate alone does not establish these separate properties. The provider,
memory and cleanup guard proofs/compiled feedback checks are currently being
completed as part of their unaccepted feature slices.

## Exact properties

| ID | Property | What remains outside this check |
| --- | --- | --- |
| `ARCH_IMAGE_CODEC_CONFINEMENT` | Image decoder imports and exports are confined to the dedicated worker and bounded preflight owners, including authored parts/barrels | Codec internals, heap use, lifetime races and device acceptance need separate behavioral/resource evidence |
| `ARCH_IMAGE_CODEC_PROVENANCE` | Audited image/archive dependency versions and hosted artifact hashes match the locked codec contract, with an exact image constraint and no audited dependency overrides | Dependency upgrades require a renewed source audit and behavioral/resource acceptance; this rule does not prove allocation bounds |
| `ARCH_SKILLS_VIEW_DEPENDENCIES` | Completed skills/Hub/detail/editor views cannot import canonical raw profile adapters | Child admission, mutation/ACK/readback and operation tracker lifetime require behavior checks; see `rules/skills_view_dependencies.md` |
| `ARCH_FIND_VIEW_DEPENDENCIES` | Find view cannot import canonical raw history/runtime adapters | Captured read/selection authority and one active viewport window require behavior checks; see `rules/find_view_dependencies.md` |
| `ARCH_CONNECTORS_VIEW_DEPENDENCIES` | Typed connector views avoid canonical raw profile adapters | Finite declared boundary; see `rules/connectors_view_dependencies.md` |
| `ARCH_MCP_SETUP_VIEW_DEPENDENCIES` | Typed setup view avoids canonical raw profile adapters | Finite declared boundary; see `rules/mcp_setup_view_dependencies.md` |
| `ARCH_OUTPUTS_VIEW_DEPENDENCIES` | Output views avoid history/preview/delivery adapter namespaces | Finite declared boundary; see `rules/outputs_view_dependencies.md` |
| `ARCH_DOWNLOAD_FILE_VALUE` | Published download bytes use the canonical sealed copied read-only value | Finite declared boundary; see `rules/download_file_value.md` |
| `ARCH_LOGS_VIEW_DEPENDENCIES` | Logs view avoids canonical raw profile adapters | Captured query/lifetime needs behavior checks; see `rules/logs_view_dependencies.md` |
| `ARCH_CONNECTOR_DETAIL_MOUNT` | Canonical borrowed child refresh starts in its explicit post-frame callback | Finite call syntax, not arbitrary async/alias analysis; see `rules/connector_detail_mount.md` |
| `ARCH_VOICE_VIEW_DEPENDENCIES` | Voice view avoids canonical raw profile adapters | Typed captured owner; finite dependency boundary, not lifetime proof |
| `ARCH_SPEECH_SYNTHESIS_VIEW_DEPENDENCIES` | Synthesis view avoids raw profile and native/player adapters | Existing typed owner delegates preview; saved-profile/ACK lifetime uses behavioral controls |
| `ARCH_PLUGINS_VIEW_DEPENDENCIES` | Plugins view avoids raw scoped profile adapters | Captured owner; ACK/lifetime and runtime activation remain behavioral/protocol properties |
| `ARCH_WORKSPACE_ENTRY_KEY_OWNER` | Remembered instance key capture and canonical preference operations stay in AppPreferences | Exact key ownership; admission/ACK/lifetime remain behavioral properties |
| `ARCH_USAGE_VIEW_DEPENDENCIES` | Dashboard uses captured usage owner instead of raw aggregate readers | Dependency prevention; partial merge and lifetime remain behavioral properties |
| `ARCH_READING_VIEW_INPUT` | Two completed reading leaves retain non-null final inputs from the canonical pure transcript model | It does not prove copying, rendering semantics or temporal authority; see `rules/reading_view_inputs.md` |
| `ARCH_TOOL_SETUP_VIEW_DEPENDENCIES` | Completed tool setup/model view libraries cannot import or receive exported canonical raw profile adapters; typed owner dependencies remain allowed | Temporal dispatch, child retirement, acknowledgement and readback still require behavior checks; see `rules/tool_setup_view_dependencies.md` |
| `ARCH_COMPLETED_MODEL_VIEW` | Completed model views cannot call canonical transport owners, parse model wire DTOs, or index reserved wire model fields | Explicit completed-view scope, provenance and semantic limitations are documented in the independent rule contract; it does not classify every business policy |
| `ARCH_OWNED_MODEL_MUTATION` | Completed model/settings/provider mutation owners use explicit caller dispatch authority and the strict physical write capability, including inherited/extension tear-offs | Scope and canonical member provenance are finite; late completion, timeout settlement and remote uncertainty require controlled behavioral regressions; see `rules/owned_model_mutation.md` |
| `ARCH_OVERVIEW_VIEW_WIRE` | The completed overview view cannot issue canonical administration transport operations or interpret reserved stock fields | The rule does not prove every arbitrary business expression or asynchronous lifetime; see `plans/001-overview-owner-regression-contract.md` |
| `ARCH_PROVIDER_VIEW_PROTOCOL` | Completed provider inventory/credential views cannot call canonical transport or wire parsing capabilities | The provider recovery detail slice is not certified; device cancellation, unknown-start uncertainty and secret lifetime need behavioral acceptance; see `rules/provider_view_protocol.md` |
| `ARCH_MEMORY_VIEW_PROTOCOL` | Completed memory views cannot call canonical transport or reconstruct/parse stock memory wire identities | Exact identity mappings and retained malformed-refresh behavior need owner/route regressions; see `rules/memory_view_protocol.md` |
| `ARCH_DELETED_DRAFT_CLEANUP_BOUNDARY` | The deleted-draft controller cleanup method and receipt store cannot perform raw filesystem cleanup or use the lenient attachment removal capability instead of the strict validated batch | Journal ordering, restart persistence, complete-batch validation and filesystem races need behavioral evidence; see `rules/deleted_draft_cleanup_boundary.md` |
| `ARCH_TASK_VIEW_PROTOCOL` | Scheduled-task views cannot issue or capture operations from the canonical task repository or profile administration transport | Resolved declaration identity determines findings; unresolved/conditional candidates fail as input errors. It does not infer arbitrary business policy or prove asynchronous ownership; see `plans/001-task-pilot-regression-contract.md` |
| `ARCH_DOMAIN_DEPENDENCY` | Domain libraries do not depend, directly or through authored barrels/utilities, on controller/data/UI/platform roles or enumerated I/O/rendering imports | It does not infer business meaning or classify every third-party package |
| `ARCH_BUSINESS_VIEW_DEPENDENCY` | Application/data libraries do not depend on view/presentation/composition roles or Material/Cupertino rendering imports | Widgets framework lifecycle glue is allowed; rendering resources have their separate rule |
| `ARCH_BUSINESS_RENDERING_TYPE` | Known rendering/focus/controller types imported from Flutter widgets/material/cupertino are absent from application/data bodies, including prefixes, explicit typedef bodies and actual parts | This is parsed import/type provenance, not complete semantic resolution. Re-exported framework types, inferred/static accesses, extension dispatch and custom wrappers need semantic enforcement or a behavioral/compiler guard |
| `ARCH_LIBRARY_CYCLE` | Every authored import/export/conditional edge lies outside a directed library cycle; actual `part` files share their owner | A package/framework cycle outside authored `lib/` is not an application cycle |
| `ARCH_DART_MAIN_ROOT_COVERAGE` | Every authored top-level Dart `main` belongs to an explicitly declared executable root or the typed host-test discovery root | It does not establish dynamic/native/other-language roots, runnable entrypoints or declaration liveness. See `rules/dart_main_roots.md`. |
| `ARCH_COMPLETED_SETUP_VIEW` | Completed connection setup delegates candidate, authentication, probe and saved-descriptor operations to its route owner | Selected setup-view scope; static operation boundaries do not prove cancellation, handoff or lifetime semantics. See `rules/completed_setup_view.md`. |
| `ARCH_APP_PREFERENCES_VIEW` | Completed appearance, text-size and composer settings views do not access raw preference storage | Three explicit views, including parts/private helpers; passive owner controls and forwarded voice storage remain allowed. Temporal save/reload/dispatch safety needs behavioral tests. See `rules/app_preferences_view.md`. |
| `ARCH_VISIBILITY_KEY_OWNER` | Canonical session-visibility preference keys are accessed through AppPreferences | Resolved key-owner boundary; arbitrary computed keys and temporal visibility behavior require behavioral tests. See `../../plans/001-app-preferences-contract.md`. |
| `ARCH_BACKUP_OWNER_BOUNDARY` | Backup service, platform adapter and selected dialogs retain their explicit responsibilities | Finite resolved access boundary; password bytes, transaction admission and rollback need behavioral tests. See `rules/backup_owner_boundary.md`. |
| `ARCH_APP_PREFERENCES_CONSTRUCTION` | Canonical app preference construction belongs in top-level bootstrap | Placement only; shared identity and lifetime behavior require the public composition regression. See `rules/app_preferences_construction.md`. |
| `ARCH_PROFILES_MANAGEMENT_VIEW` | The completed profiles view accepts its typed session factory and cannot regain canonical transport/domain policy or untyped protocol maps | Finite resolved namespace/type/member boundary; ACK identity, pending settlement and dispatch lifetime need behavioral tests. See `rules/profiles_management_view.md`. |
| `ARCH_PROFILE_IDENTITY_VIEW` | The completed identity view delegates to its supplied session and cannot regain canonical transport, metadata codecs or identity policy | Finite canonical boundary; conflict preflight, field independence, uncertainty and notification retirement need behavioral tests. See `rules/profile_identity_view.md`. |
| `ARCH_PROFILE_COLOURS_VIEW` | Profile selector and chat bar delegate colour persistence to their supplied session and cannot regain canonical storage, key encoding, native channel authority or session construction | Finite canonical boundary; false acknowledgements, FIFO admission, picker retirement, restoration and reload recovery need behavioural tests. See `rules/profile_colours_view.md`. |
| `ARCH_BROWSER_ROW_WORK` | A single streamed browser row cannot regain the canonical connection-wide browser index accessor, including captured initialized aliases | Finite canonical member boundary; supplied callback and interprocedural costs still require the existing zero-index-read and zero-rebuild streaming tests. See `rules/browser_row_work.md`. |
| `ARCH_NOTIFICATION_JOURNAL_ACK` | Canonical notification journal writes cannot discard the actual SharedPreferences boolean acknowledgement at the enumerated direct-expression sites | Finite canonical member/result boundary; merely storing the result does not prove settlement. Policy stability, journal durability and retries require the notification behavioral regressions. See `rules/notification_journal_ack.md`. |
| `ARCH_AUTHORED_CENSUS` | The actual present tracked/intentional untracked checkout file set equals the root manifest census, with no duplicate entries | It does not establish executable-root completeness or declaration liveness; Git ignore policy still needs review. See `rules/authored_census.md`. |
| `ARCH_ROLE_INVENTORY` | Every authored `lib/**/*.dart` file has one valid role/feature and its actual containing library; absent/stale/mismatched part ownership fails | Role labels need independent ownership review; the manifest cannot establish that business rules left a view |
| `ARCH_VIEW_LOWLEVEL_DEPENDENCY` | View libraries do not directly import enumerated HTTP/socket/storage/file adapters | Feature-controller imports are allowed. Local adapter construction, endpoint strings, method-channel calls and business assignments need resolved-symbol/private-interface guards; a generic `flutter/services.dart` import is allowed for genuine UI utilities |
| `ARCH_VIEW_DRAFT_WRITE` | View/presentation libraries do not write the resolved `ProfileChat.draft` property, including aliases, cascades, increments and extension bodies | A syntax prefilter selects candidates; only actual declaration provenance produces a violation. Dynamic or conditional candidate provenance fails as unsupported input. It does not prove durable ordering or detect writes to other business facts. |
| `ARCH_RETIRED_DECLARATION` | Canonical library/member identities in the reviewed retirement manifest remain absent, including declarations in actual parts | It protects explicit retired APIs, not every unused public member or equivalent renamed implementation. Root-aware semantic inventories establish deletion evidence. |
| `FIXTURE_MODEL_CATALOG` | The local fixture emits literal provider rows with canonical slug/name/string model IDs | Python AST/import provenance identifies the actual catalog response. Computed/multiple responses require explicit guard adaptation. Other same-name data is allowed. This does not certify every API fixture against upstream. |
| `FIXTURE_RETIRED_RECOVERY` | The retired ledger file and its canonical import identities stay absent from the fixture | Unrelated modules with the same leaf name and negative unsupported-RPC probes are valid. Live fixture regressions also reject obsolete methods/submit fields and check ready capabilities. |
| `STOCK_TASK_BLUEPRINT_SCHEMA` | Advertised blueprint form schemas equal the source-bound stock projection, with declared dynamic delivery options | The independent JSON guard does not parse Dart. Mandatory host tests export the actual fixture response and invoke it. Other blueprint rendering fields are outside this property. |
| `STOCK_TASK_BLUEPRINT_SLOT` | Captured template submissions use only stock slot names for the selected blueprint | Values, defaults and optional-field semantics remain server authoritative. Mandatory host tests export actual fixture requests; this rule does not establish server mutation acceptance. |
| `ARCH_MODEL_CATALOG_FIXTURE` | Literal returned catalogs beneath `model/options` equality branches or constant switch-expression cases use slug/name/string model IDs, including conditional list rows | This is a parsed syntax contract for fixture producers, not resolved HTTP routing. Computed catalogs in those branches fail as unsupported input. Other route-dispatch forms need explicit adaptation; unrelated responses and negative parser-input literals are allowed. |

All conditional URIs are checked regardless of the current host platform.
Relative and `package:wing/` URIs identify the same authored files. Exports and
barrels cannot conceal a domain/business dependency. Library identity comes
from actual `part` declarations; arbitrary manifest grouping fails inventory.
Standard analysis remains responsible for Dart semantic/syntax validity.

There is no changed-file mode yet. Every run reads the full authored scope, so
deleted files, reverse importers and conditional/barrel paths cannot disappear
from an incremental shortcut. There is no network lookup or runtime policy
dependent on the clock. The graph snapshot is parsed fresh; selected semantic
guards reuse standard analyzer summaries with source/configuration/SDK bindings
outside tracked source. Every invocation recomputes its findings.

Draft ownership fixtures run independently with
`dart run tools/architecture/tests/view_draft_write_test.dart` and through the
ordinary host suite. They prove invalid/valid/input-error CLI exits and semantic
identity. Clean production starts no resolver. Measured source startup remains
within the existing 10-second local budget; the aggregate shares parsing and the
compiled path amortizes SDK startup. Recheck the compiled 0.5-second budget when
rolling out the new rule. Semantic fixture execution is separate test setup cost.

## Migration baseline

`baseline.json` is empty after cleanup. Its migration format uses keys comprising rule
ID, relative file and semantic subject. Line numbers are diagnostics, not keys;
formatting does not create a new exemption. Repeated import/type occurrences
have distinct ordinal subjects, so adding another existing bad pattern fails.
Cycle diagnostics identify individual cyclic edges, allowing a cycle to shrink
without inventing a new exemption for a smaller strongly connected component.

Normal checks reject new violations and stale entries. Delete the matching
baseline entry when its source violation is removed. Do not regenerate the
baseline after a failed check. There is intentionally no rebaseline command.

CLI options:

- `--root PATH`: authored checkout, containing `lib/`.
- `--roles PATH`, `--baseline PATH`: explicit schema-1 manifests.
- `--baseline-reference PATH`: reject exemptions added relative to the previous
  reviewed baseline; CI supplies the PR base/push-before snapshot when present.
- `--strict`: report every source violation without migration suppression.
- `--json`: deterministic ordered diagnostics plus informational timing fields.

Exit 0 means no blocking findings against the selected rules and baseline; exit
1 means a rule or migration contract failed; exit 2 means invalid input/options.
Individual-rule runs check stale entries only for their own ID; full runs check
all aggregate IDs. Closing the architecture program requires the empty baseline and a
strict run, plus the semantic/native/manual acceptance in the program.

## Fixtures and failure proof

`fixtures/contracts.fixture.json` is data, not analyzer-visible invalid Dart.
Tests materialize isolated temporary workspaces and role manifests. Fixtures
cover relative/package/conditional imports, exported barrels, real parts,
cycles, prefixes, typedefs, local name shadowing, rendering lifecycle exceptions,
missing/stale roles and permitted typed feature access. Baseline tests cover
second occurrences, formatting, stale entries, duplicates and the shrink-only
reference contract. The aggregate CLI is exercised as a real child process.
Each independent CLI is also checked with its corresponding invalid/valid
fixture during phase-0 acceptance; evidence belongs outside tracked source.

## Fast local feedback

SDK/analyzer source startup dominates tiny rules. For repeated local checks,
compile the same aggregate once and execute it with shared parsed input:

```sh
mkdir -p build/architecture
dart compile exe tools/architecture/check_all.dart -o build/architecture/check_all
build/architecture/check_all
```

Recompile after guard-source, SDK or resolved dependency changes. Role/baseline
and production source files are read fresh on every invocation. CI uses the
source command so a stale local executable cannot establish acceptance.

The initial local feedback budgets for the phase-0 checkout are 0.5 seconds
median end-to-end for the compiled aggregate and 10 seconds median for source
startup, measured over at least five/three repeated runs respectively on the
same host/SDK and 252 authored files. These budgets provide roughly 2.5x/1.3x
headroom over the observed maxima during acceptance; the compiled path is the
intended edit-feedback route. Recheck budgets with the same workload when new
rules roll out. Investigate a reproducible regression rather than silently
raising a budget. Compilation is setup cost and is reported separately.

Timings never change correctness results or fail noisy CI. Record host, SDK,
input size, cold startup, repeated runs and per-rule/in-process timings in
ignored/private execution evidence. These are guard-feedback budgets, not
application latency, memory or battery acceptance.

The independent Python fixture guards have a 100-millisecond median local
startup budget each, with a 200-millisecond combined budget for model-catalog
and recovery-retirement feedback. Blueprint guard inputs cover all 16 schemas
and 58 fields; their commands and source-update procedure are documented in
`tools/contracts/README.md`. Measure cold startup and at least three warm runs
on the same host and Python version. These informational budgets do not change
diagnostics or introduce timing failures in CI.


The browser-row and notification-acknowledgment commands retain independent
source/compiled feedback budgets of 10 seconds and 0.5 seconds. First-use and
warm runs are measured separately against immutable registered inputs, with
correctness fixtures completed beforehand. The optimized acknowledgment rule
retains all original 45 cases and passes 64 total controls. Timing is recorded
privately under the performance procedure and never changes a deterministic
finding or CI exit code. These boundaries do not establish that all browser
business logic has left the view.

`ARCH_WORKSPACE_SEARCH_OWNER` keeps interactive search in `ChatBrowserData`, allowing canonical workspace gateway search only in its three metadata seams. Scope and limitations: [workspace search owner](workspace_search_owner.md). Run its finite fixtures with `dart run tools/architecture/tests/workspace_search_owner_test.dart`.

`NATIVE_NOTIFICATION_RETIRED_ACTION` rejects the removed bulk notification channel action; retained per-ID cancellation is allowed. Run `python3 tools/architecture/native_notification/retired_action.py` and `python3 tools/architecture/native_notification/prove_boundary.py` after normal native dependency setup. Its [finite contract](native_notification/README.md) states parsing limits.

`ARCH_TRANSCRIPT_HISTORY_DISPATCH` protects the actual history intent callback: explicit button events remain direct, automatic scroll requests run after the frame. Its [finite syntax scope](rules/transcript_history_dispatch.md) complements the renderer coalescing, disposal and streaming-anchor regressions.

`ARCH_RECENT_CAPTURE_RELEASE_SAFE` resolves the actual Flutter debug paint getter in the canonical Recents capture library and rejects reads outside assertions. Its [scope and release regression](rules/recent_capture_release_safe.md) distinguish SDK identity from same-named getters; captured pixels and signed-release interaction remain behavioral checks.

Retirement manifest schema 2 requires every declaration entry to state `kind: any` (all declarations of that exact symbol) or `kind: field` (only fields). A retained named constructor can share a retired field name. Old schemas and missing kinds fail with input exit 2.

`ARCH_PROFILE_DISCOVERY_WRITER` restricts canonical discovery publication to its private adoption seam. [Its finite scope](rules/profile_discovery_writer.md) complements the behavior checks for unchanged discovery identity, changed immutable membership and token updates without list rebuilds. Fixtures: `dart run tools/architecture/tests/profile_discovery_writer_test.dart`.

`NATIVE_RETIRED_DECLARATION` protects the exact removed monitoring summary constant and notification handle constructor option. [Its finite contract](native_notification/retired_declarations.md) retains live per-ID notifications, the injected clock and UUID generation. Run `python3 tools/architecture/native_notification/retired_declaration.py` and `python3 tools/architecture/native_notification/prove_declarations.py` after normal native setup.

`NATIVE_VOICE_PERMISSION_LIFECYCLE` keeps pending microphone permission retirement
out of media pause and connects it to foreground retirement. Run
`python3 tools/architecture/native_voice/permission_lifecycle.py` after native
setup. Its [finite contract and shared fixture driver](native_voice/README.md#permission-lifecycle-ownership)
retain the real Android denial/grant/Home fixture as the lifecycle-order check.

`ARCH_SAVED_PROMPT_JOURNAL_ADMISSION` protects the two canonical saved-prompt journal → owner admission → reading stage → acceptance sequences. [Finite scope and behavior limits](rules/saved_prompt_journal_admission.md). Fixtures: `dart run tools/architecture/tests/saved_prompt_journal_admission_test.dart`.

`ARCH_RETIRED_ANSWER_VERSIONS_NAMESPACE` rejects the exact retired answer-version preference prefix in the canonical workspace library. [Finite literal/part scope](rules/retired_answer_versions_namespace.md). Fixtures: `dart run tools/architecture/tests/retired_answer_versions_namespace_test.dart`.

`ARCH_CURRENT_TOOL_EVENTS` rejects unsupported event spellings and top-level aliases at the canonical tool parser/dispatch seams. [Finite contract](rules/current_tool_events.md). Fixtures: `dart run tools/architecture/tests/current_tool_events_test.dart`.

`ARCH_INTELLIGENCE_READ_ADMISSION` keeps captured read admission directly around
the canonical workspace's awaited model-settings read. Its [finite contract](rules/intelligence_read_admission.md)
distinguishes structural placement from the held-I/O freshness regressions.
Fixtures: `flutter test --no-pub test/intelligence_read_admission_guard_test.dart`.

## Compact activity headers

[ARCH_ACTIVITY_DENSITY](rules/activity_density.md) requires tool and saved-agent
header builders to return the canonical shared row directly. It resolves
constructor identity, accepts prefixes/barrels/typedefs, and leaves spacing
inside expanded details or unrelated controls alone. Rendered tests establish
actual zero-padding geometry; the linter only protects the construction seam.
The rule runs in the aggregate and independently in both quality workflows;
required-gate fixtures reject omissions and swallowed failures.

```sh
dart run tools/architecture/rules/activity_density.dart --json
dart run tools/architecture/tests/activity_density_test.dart
flutter test --no-pub test/activity_density_guard_test.dart \
  test/profile_activity_details_layout_test.dart
```
