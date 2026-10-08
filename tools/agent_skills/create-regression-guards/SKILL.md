---
name: create-regression-guards
description: Turn discovered incorrect patterns into small, independent, deterministic linters or behavioral regression guards during codebase cleanup and refactoring.
---

# Create regression guards

For **every discovered incorrect pattern**, decide how its recurrence will be
detected. Produce a working guard or record the exact reason static detection is
unsuitable and supply a behavioral guard. A code fix alone does not close the
finding. Load this repo-local skill by path; global installation is unnecessary.

## Define the property

Read the applicable project instructions and existing lint/test/CI configuration.
For each finding, record in the implementation ledger:

- The actual symptom, affected production path and observable invariant.
- The property to detect, its scope and legitimate cases it must accept.
- An existing or new stable diagnostic/rule ID, remedy and verification command.
- The static-feasibility decision and evidence. For a behavioral-only guard,
  state what information static analysis cannot establish and link the regression.

Group findings enforcing the same property under one rule. Separate properties
that need different valid-case exemptions or remedies. Establish a minimal
counterexample before designing the detector.

## Keep each linter small and independent

Create many focused linters, each enforcing one named property with its own
diagnostic ID, runnable command and fixtures. Share parsing and graph helpers
where useful; keep rule logic independently inspectable and executable. A
lightweight aggregate runner only selects/invokes rules and combines their
diagnostics and exit status. Keep business decisions in individual rules rather
than building a monolithic plugin or framework.

Run locally and deterministically: stable diagnostic ordering, no network, model
calls or wall-clock-dependent decisions. Measure and record each rule's runtime
and the aggregate runtime on stated fixture/codebase sizes. Optimize demonstrated
costs; do not invent a universal runtime ceiling. Runtime measurement itself is
observational and must not change the rule's result.
Establish justified numeric local-feedback budgets from cold startup and repeated
warm runs on the actual checkout before rolling out further rules. Record the
host/SDK/input size; compare later acceptance benchmarks under the same conditions.
Optimize regressions rather than silently raising the budgets. Keep noisy CI
timing informational so it cannot change the deterministic correctness verdict.
If SDK/parser startup dominates a tiny rule, measure a compiled entry point or
invoke independent rules in one process with shared immutable parsed input.
Keep each rule's own command and fixtures; amortize tooling startup without
combining unrelated rule logic. Cache only with source/configuration/SDK-aware
invalidation, outside tracked source.

## Choose the narrowest effective guard

1. Reuse standard Dart/Flutter analyzer diagnostics and lints first. Verify the
   repository's installed SDK supports the chosen rule and that CI treats its
   diagnostic as a failure.
2. For a project-specific Dart property, use the cheapest precise representation:
   parsed AST or library/import graph when sufficient, resolved symbols when the
   actual property requires semantic identity. Account for imports, exports and
   re-exports, parts, conditional imports, prefixes, type aliases, extension
   dispatch and cascades wherever they can affect that rule. Match symbol
   ownership and semantic operations when necessary, rather than variable
   spelling. Test applicable alternate spellings and graph paths.
3. For Kotlin, use an appropriate rule in the existing Android build/static
   tooling when feasible; verify the actual build target invokes it. A source
   search is an inventory aid, not a proof of thread or lifecycle correctness.
4. For races, persistence ordering, cancellation, resource limits or protocol
   uncertainty, add behavioral/regression/property checks at the active module
   interface. Control event order and failed/held I/O. A structural rule can
   support these tests, but must not claim to establish their semantic outcome.

Use existing tooling and compatible project dependencies. Do not install a
framework or upgrade SDK/library versions merely to obtain linting. If suitable
static tooling is unavailable, record the precise limitation and use an effective
alternative guard within scope. Regex over business source and brittle
raw-source assertions do not establish an architecture property. Blanket bans on
async code, file size or method size do not replace a demonstrated invariant.

## Prove detection and acceptance

For each static rule, add minimal **invalid fixtures** producing its diagnostic
and **valid fixtures** covering legitimate nearby patterns. Include indirection
or syntax variants that could bypass the rule, and ensure unrelated symbols with
the same spelling remain valid. Assert diagnostic identity and relevant location,
not implementation wording or analyzer-private structure.

Run a red check before relying on the guard: show the bad fixture fails the exact
command CI will invoke with a nonzero status. Show valid fixtures pass, including
the repaired production pattern. Keep deliberately invalid fixtures outside the
ordinary production-analysis target while testing them through the rule runner.
For behavioral guards, demonstrate failure against the original behavior, then
pass after the fix; use a temporary isolated reproduction when reverting source
would interfere with concurrent work.

Wire guards into the relevant existing CI gate and contributor verification
command. Prove the gate cannot silently omit the runner or swallow its failure.
Use changed-file runs for local feedback only when the property is local; graph
rules must include affected importers, exporters, parts and dependency closure,
including deleted/renamed files. Invalidate shared caches on relevant source,
configuration or SDK changes. Run the complete production scope in CI and prove
incremental results agree with a full run for representative cross-file changes.
Run focused verification and the project's required checks for the batch.

## Handle migration without hiding regressions

When existing violations require staged cleanup, baseline exact scoped findings
with diagnostic IDs and reasons. Reject new findings; allow the baseline only to
shrink. Final architecture acceptance requires a zero baseline. Suppressions must
name a justified valid case, use the narrowest scope and be removed when their
reason disappears. Re-run guards after deletions to catch newly dead helpers.

For Wing, follow its current unmodified-upstream Hermes constraint and record the
inspected revision for protocol rules. Backend changes and invented fixture
protocols cannot repair a client guard. Obtain explicit approval before adding or
preserving backward-compatibility behavior.

## Complete the batch

Every finding has a linked guard, its verification result and any precise static
limitation. Every new rule has an independent command, invalid and valid fixtures,
measured runtime and CI failure proof.
The ledger distinguishes structural enforcement from behavioral evidence; it
never claims that linting proves all business logic has left the UI. An unresolved
property remains open rather than being closed by a passing unrelated check.

If parallel work is authorized, delegate bounded rule or fixture tasks with
explicit owned files and acceptance checks. Do not assume model choices or token
budgets; inspect and verify the returned artifacts before accepting them.
