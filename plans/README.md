# Make Wing straightforward to change

Purpose: one owner for each business fact, presentation-only views, cohesive
modules, small interfaces, removed dead code and deterministic prevention of
encountered incorrect patterns. Production migrations and subtraction take
priority. Verify changed contracts and broader integration milestones.

Follow the [original program](001-clean-architecture-program.md),
[verification contracts](001-clean-architecture-verification.md),
[architecture map](../docs/ARCHITECTURE.md),
[feature inventory](001-feature-inventory.md) and
[dead-code disposition](001-dead-code-inventory.md). The reusable
[guard-writing skill](../tools/agent_skills/create-regression-guards/SKILL.md)
is available to agents by path. The user started this program on 3 October 2026.

| Phase | Outcome | Status |
| --- | --- | --- |
| 0 | Initial ownership/root/dead-code inventory; linters and CI baseline | DONE |
| 1 | Ownership/data-loss fixes and durable prevention | DONE |
| 2 | Inactive paths deleted; dependency inversions removed | DONE |
| 3 | Complete task/model/diagnostics owner pilot | DONE |
| 4 | Every remaining feature migrated or reviewed against the target | DONE |
| 5 | Conversation facts and lifetimes have explicit owners | DONE |
| 6 | Native/resource responsiveness and matched phone performance | IN PROGRESS |
| 7 | Whole-checkout finite dead-code/root closure and prevention | DONE |
| 8 | Independent review and final device/current-stock acceptance | IN PROGRESS |

Seven original phases are complete; two retain acceptance obligations. Phase
completion follows the original gates. The remaining device/performance/server
requirements prevent whole-program completion.

## Accepted architecture and subtraction

The current reviewed source contains 1,500 authored files, 358 production Dart
files, 348 libraries and 143 views. All production files received full source
review and explicit reviewed-delta supplements. The architecture map names 29
responsibility boundaries; the feature inventory has no unexplained view row.
Three independent change-locality traces cover pending input, model assignment
and stock answer mapping.

Conversation facts have separate owners: `ComposerSession` owns unsent work and
ordered persistence; `TranscriptReading` owns immutable history and paging;
`ChatRuntime` owns execution, recovery and pending input; the workspace coordinates
captured transport and lifetime admission. Views forward commands and render
observations. Feature owners retain configuration baselines, conflicts, readback,
OAuth/operation polling and scoped mutations. Business facts are not writable
through views or peer owners.

The finite reviewed deletion inventory has zero confirmed or deferred deletion
leads, and the migration baseline is empty. The existing retirement guard protects
809 exact removed identities. There are 67 independently runnable Dart linters,
with invalid/valid fixtures and mandatory CI enforcement, plus five native guard
properties and the Python checks. Static checks protect precise properties; held-I/O and event-order
regressions cover lifetime, durability and uncertainty.

The last runtime correction separates `rejectSavedPromptEdit` from
`rejectRegeneration`. Physical dispatch does not decide conversation execution:
a definite edit rejection restores captured execution, while the existing
regeneration-failure behavior remains explicit. The obsolete ambiguous command
is removed and guarded. Actual rejection, lost-ACK and journal-held disposal
regressions protect the semantic distinction.

## Accepted local verification

Current analysis, all mandatory production architecture commands, ordinary Android
APK build, product-mode instrumentation and pinned Chromium renderer isolation
pass. Composed host coverage spans all 464 default test files: 3,833 unique actual
passes, 17 documented skips and no remaining failure. This is completed file
coverage plus the final affected-file rerun, not one uninterrupted green runner.
The failed predecessor and erroneous nonexistent-file command remain recorded
and are excluded from accepted totals.

Native source/root review, nine native guard/proof commands and 27 JVM controls
cover the final source, with scoped predecessor reuse where source is unchanged. Sixty-four affected
normal/enlarged light/dark renders were inspected. These checks do not certify
physical-phone performance or a deployed server. Exact source/APK/test bindings,
skips and successor dispositions live in ignored `build/architecture-program/`;
private device captures remain outside Git under the performance policy.

The installed disposable-emulator monitoring, seven file/photo/share cases, and
held-provider intake/camera-recreation journeys pass. Their private receipts record
source bindings, retained build hashes and any unaffected-source reuse. Native voice now separates media
pause from foreground retirement: a permission dialog cannot cancel its own
request through `onPause`. A separate Kotlin linter protects that boundary and
its actual original counterexample; the existing device fixture retains the
denial, grant and Home assertions.

## Remaining acceptance

- Finish installed voice denial/grant/background/transfer acceptance. Two attempts
  lost the Flutter VM connection before assertions; source/JVM/linter checks do
  not replace this device result.
- Run matched profile-mode physical-phone resource/performance checks and normal
  and restricted battery/network behavior on an authorized QA phone.
- Run applicable stock runtime journeys against an authorized owned QA profile/chat
  on latest upstream unmodified Hermes. The latest inspected source is
  `e473f5a9c976a0b5bc292aa415dae28c638a47c3`; its gateway/router contracts match
  the preceding inspected revision. Source review is not deployed acceptance.

No additional production migration or confirmed deletion lead remains open in
this reviewed inventory. An actual final finding still requires a bounded fix,
prevention decision and affected verification. Do not start another generic
cleanup framework or repeat unaffected tests to increase totals.

## Continuing changes

Find the canonical owner in the architecture map; assign explicit module/file
ownership before parallel edits. Update relevant interfaces, callers and role
records together. Ordinary UI edits do not require global audit SHA-map updates.
Prefer small, direct replacements and remove superseded code in the same batch.
Protect each encountered incorrect pattern with an existing or small new linter
where sound; use semantic regressions when static detection cannot establish it.

Work client-only against current stock Hermes. Backend changes, deployment and
external mutations require separate authorization. Backward compatibility
requires explicit user approval. Preserve Studio appearance, supported behavior,
captured scope, uncertainty, durability and unrelated changes.
