# ARCH_ACTIVITY_DENSITY

Tool and saved-agent headers previously repeated their own tile geometry. A
normal Material tile's padding/minimum height made low-information rows grow
large gaps. The shared `CompactActivityRow` now owns the text-sized header with
zero vertical padding, no minimum height and no inter-row gap. Callers supply
text lines, an icon, delivered timing, optional details and disclosure state;
they cannot override header spacing. Empty details produce a passive row.

The independent guard requires `ProfileToolCall.build` and
`ProfileSavedAgents._buildAgent`, in their exact physical libraries, to return
that row directly. It examines all method-level return expressions, including
branches and expression bodies; callback/local-function returns have separate
contracts. Constructor identity must resolve to `CompactActivityRow` in
`lib/core/widgets/compact_activity_row.dart`, accepting parenthesized calls,
prefixed imports, re-exported barrels, named constructor syntax and typedefs.
Same-spelling local/imported classes are rejected. A padding/container/minimum-
height wrapper, alternate tile, helper return or constructor-tearoff invocation
produces exit 1 with the stable ID, file, line and return-site subject. Construct
the canonical row directly to repair it. No baseline exemption applies.

Missing/ambiguous owners or methods, absent implementations/returns, source or
semantic errors, and parts/conditional imports on the three protected physical
libraries fail closed with `[ARCH_INPUT]`, exit 2. Clean input exits 0. This is a
finite construction seam, not arbitrary value-flow analysis. It does not inspect
every transitive dependency's platform branches, traverse helpers or prove
pixel geometry, timer lifetime, touch behavior or the presence of real output.
Standard analysis and the behavioral checks below complement that scope.

Expanded detail content may retain padding, images, Markdown and its normal
controls. Unrelated settings/action UI may retain normal touch-friendly spacing.
Strongly typed text/timing header slots prevent inserting arbitrary layout
wrappers into the header without changing the shared interface.

The rendered regression in `test/profile_activity_details_layout_test.dart`
measures the top/bottom bounds of every collapsed row and its contiguous text
lines, plus adjacency and the actual saved-history section, tool-group wrappers and
automatically discovered activity-tab body. The allowed height is
exactly the tallest parallel column (text, timing or icon), not the sum of text
and timing heights. Duration labels must match their own natural text height
and start at the top of the row, so internal or surrounding timer padding cannot
inflate that budget. Fixtures cover targets, errors, wrapped supplied labels,
delivered tool/agent durations, model/API metadata and whitespace-only agent
output in both themes at normal and doubled text. The same cases execute on
Android through `integration_test/profile_expansion_scroll_test.dart`.
Static analysis cannot establish actual rendered bounds, text wrapping, theme
insets or parent spacing; these properties have behavioral enforcement.

Forty-eight independent detector fixtures run both protected seams, accepting
legitimate nearby patterns and rejecting wrappers, helper/tearoff indirection,
homonyms, malformed/unresolved input and unsupported owner namespace shapes.
Three invoke the exact source CLI and assert exits 0/1/2 and diagnostic location.
The fixture root is reused across edits, exercising analyzer summary invalidation
on changed sources and imports. No rule results are cached.

```sh
dart run tools/architecture/rules/activity_density.dart --json
dart run tools/architecture/tests/activity_density_test.dart
# Optional local AOT identity/exit proof:
dart compile exe tools/architecture/rules/activity_density.dart -o build/architecture/activity_density
dart run tools/architecture/tests/activity_density_test.dart --compiled build/architecture/activity_density
flutter test --no-pub test/activity_density_guard_test.dart \
  test/profile_activity_details_layout_test.dart
```

The aggregate imports this independent rule. Both existing quality/release
workflows also invoke the source CLI and fixtures directly. The required-gate
inventory and its omission/soft-failure regressions protect those steps. The
tracked commit hook discovers the rule through the aggregate.

For local feedback, compile this entry point (or the aggregate), recompile after
guard/SDK/dependency changes, and execute against freshly read production input.
Measure cold startup, at least three warm source runs and five compiled runs on
the same checkout/SDK; retain host, input count, source binding and timings in
private evidence per `docs/PERFORMANCE.md`. Compare with the established aggregate
feedback budgets before accepting a rollout. CI timing remains informational,
and never changes the deterministic correctness verdict.

The scoped local-feedback budgets for this rule are 30 seconds for cold source
startup, 12 seconds for warm source startup and 2 seconds for warm compiled
execution on the acceptance host/SDK/input. They account for semantic constructor
resolution, rather than pretending this is a token-only check. Record their
acceptance measurements privately and recheck under the same conditions after
changes. Keep the historical phase-0 aggregate budgets unchanged: compare the
current aggregate with and without this rule to separate its cost from existing
resolver work and checkout growth. An unrelated existing aggregate-budget excess
must be recorded explicitly, rather than hidden by increasing that budget.
