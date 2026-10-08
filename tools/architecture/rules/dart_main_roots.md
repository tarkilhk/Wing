# Dart executable root coverage

`ARCH_DART_MAIN_ROOT_COVERAGE` rejects authored Dart top-level `main` function
declarations missing an executable root in `tools/architecture/roots.json`.
This closes the demonstrated gap where supported new CLI/device entrypoints
were present in the file census but absent from the runtime-root inventory.
It is root coverage, not declaration liveness or proof that a root is runnable.

```sh
dart run tools/architecture/rules/dart_main_roots.dart
dart run tools/architecture/tests/dart_main_roots_test.dart
dart compile exe tools/architecture/rules/dart_main_roots.dart -o build/dart-main-roots
dart run tools/architecture/tests/dart_main_roots_test.dart --binary build/dart-main-roots
```

The command accepts only optional `--root PATH`; it uses parsed AST, without
resolved symbols or SDK discovery. Input must be an application Git checkout
(including a linked worktree). Scope is the union of present Git cached/untracked
nonignored files and census-listed files. Physically deleted tracked files are
skipped; census freshness is independently enforced by `ARCH_AUTHORED_CENSUS`.
Fixed directory exclusions are root `.git`, `build`, `.dart_tool`, and nested
`node_modules`/`__pycache__`. There are no generated/fixture suffix exemptions:
invalid fixture source belongs in string/JSON fixtures or excluded temporary
workspaces. Dart symlinks fail input rather than following external sources.

An explicit same-library root uses an existing executable kind (`dart-main`,
`alternate-dart-main`, `host-test`, `device-or-live-test`, `device-driver`,
`guard-cli`, `guard-runner`, `guard-fixture-cli`, `opt-in-qa-cli`,
`manual-or-ci-cli`, `fixture-cli`). Its optional selector names `main`, either
directly or in the current selector-list shape alongside owned build predicates.
Asset/resource rows cannot cover executable declarations. Actual relative-URI
or named parts use their containing library's entrypoint row; a part row alone
cannot make a part independently executable. Missing, duplicate, orphaned or
contradictory part ownership fails input instead of guessing a library.
Part URIs must be relative without authority, query or fragment; those components
cannot be discarded to manufacture a matching ownership path.

The only discovery shape currently supported is explicit Flutter host discovery:

```json
{
  "id": "host-test-discovery",
  "kind": "dart-test-discovery",
  "path": "test",
  "selector": {"declaration": "main", "pattern": "**/*_test.dart"},
  "purpose": "Mandatory Flutter host test discovery",
  "source": "flutter test in the quality workflows",
  "status": "supported"
}
```

This matches test files directly in `test` and its descendants, not arbitrary
helpers with `main`, `integration_test`, tooling or application directories.
Other discovery patterns require an explicit detector/fixture contract change.
Root status records disposition; supported/reference/needs-decision inventory
entries can describe a root, but this rule does not resolve product decisions.

Exit0 means complete parsed Dart-main coverage; exit1 reports deterministic
declaration path/line and rule ID; exit2 rejects invalid Git/manifest/path/parser
or part input. Comments, literals, nested functions, class methods and top-level
getters/setters named `main` are not entrypoint declarations. Diagnostics quote
paths so control characters cannot create fabricated output lines. Input errors
do not print arbitrary source or credentials.

The independent host wrapper proves invalid1/valid0/input2 actual source CLI,
public API cases and a separate actual production CLI scan. The standalone proof can exercise a freshly compiled CLI with
the same fixtures, independent of clean production findings. The PR quality and release workflows run the production CLI as a mandatory
hard-failing step; the independent required-quality guard rejects omission,
conditional execution and swallowed failures. Production inventory corrections
and all fixture/CLI proofs are separate from the whole-program closure review.

The feedback budgets are 15 seconds for the source CLI and 1 second for a freshly
compiled CLI on the declared Dart 3.12/analyzer 10.1 Linux acceptance host.
Four source and four compiled actual-production runs use identical hash-bound
Dart/census/root inputs in a quiet window before accepting these budgets.
Host configuration, input hashes and individual measurements belong in private
evidence. A new host or larger authored scope requires a measured review;
a passing correctness check alone does not establish its feedback budget.

Limitations: Python, native, JavaScript, shell, Gradle, assets, dynamic callbacks,
root-selector execution and dependency consumers are outside this Dart property.
Git-ignored files absent from the census are outside authored scope. No import
reachability, dynamic invocation, deletion approval or whole-program dead-code
claim follows from a passing result.
