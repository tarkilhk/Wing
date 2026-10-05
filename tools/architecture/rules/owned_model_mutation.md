# Owned model mutation capability

`ARCH_OWNED_MODEL_MUTATION` enforces one completed-owner boundary in the three
fixed model command owners: main model, fallback chain and helper defaults.
Canonical references to `ProfileGateway.post`/`put`,
`ProfileAdministration.write` and `AdministrationRepository.request` are
forbidden, including captured method/function tearoffs. Each owner must directly
invoke its declared owned capability (`postOwned` or `ownedMutation`). Ordinary
analyzer diagnostics permit those generic calls, so this property needs its own
rule.

```sh
dart run tools/architecture/rules/owned_model_mutation.dart
dart run tools/architecture/tests/owned_model_mutation_test.dart
```

The ordinary host wrapper is `test/owned_model_mutation_guard_test.dart`. It
checks all three production owners and runs the independent fixture command.
Twenty-seven synthetic cases prove real source and compiled CLI diagnostic/source location and exits
1 (forbidden dispatch), 0 (valid owned dispatch), and 2 (unsupported input).
The fixture command compiles one temporary guard unless passed `--compiled PATH`;
it also exercises the compiled binary outside the SDK directory, without an SDK
configuration, to prevent accidental binary-location SDK inference.
Fixtures cover receiver aliases, cascades, method/function tearoffs, parenthesized
calls, explicit `.call`, import prefixes, barrel exports, typedefs and declarations
in a transport library part, plus naked inherited/extension method and callback
captures. Unrelated symbols with identical method names, local callbacks,
declaration labels, intrinsic `Function.call`, comments and string contents remain
valid. Merely calling `toString` on an owned tearoff does not count as owned
dispatch.

The rule resolves declaration identity against the two canonical transport
libraries; it does not infer ownership from a receiver's spelling. Missing
libraries, malformed selected owners, unresolved candidate references, direct
conditional imports and selected owner parts fail with input exit 2. Dart
backslash-escaped member identifiers are malformed input, not an accepted alias.
Resolution uses the current SDK/platform configuration; transitive conditional
adapters need separate platform evidence.

The static claim is deliberately narrow: a forbidden bound reference cannot
appear in these files, and a direct bound owned invocation must appear. The rule
does not prove reachability of that invocation, inspect generic dispatch hidden
inside another library, follow arbitrary function-variable dataflow, or establish
that every path reaches the correct capability. It does not verify mutation
payloads, freshness, cancellation, timeout or HTTP retry ordering. Do not use its
green result to close those behavioral obligations.

The helpers' controlled tests in `test/profile_model_defaults_session_test.dart`
hold a dispatch gate, retire the route, or settle a consumer timeout while its
producer remains held. Releasing the old gate must produce zero POSTs; the
uncertain flag begins only when `onDispatched` actually fires. An explicit retry
uses the retained opening assignment, never a refreshed replacement baseline.
Main/fallback/settings physical-HTTP tests separately hold authentication and
exercise authority checks immediately before actual HTTP dispatch, including a
401 retry. A timeout cannot retain dispatch authority simply because the route
and generation remain live.

The helper endpoint is current stock `POST model/set`, inspected at
[Hermes db45b44ab72af81974adfb01c9ecd6967f5bec29](https://github.com/NousResearch/hermes-agent/blob/db45b44ab72af81974adfb01c9ecd6967f5bec29/hermes_cli/web_routers/models.py).
Stock offers no expected-version mutation precondition; a backend write racing
after fresh client preflight remains outside the observed-conflict guarantee.

For repeated local checks, compile the independent entry point rather than paying
SDK startup on every invocation:

```sh
dart compile exe tools/architecture/rules/owned_model_mutation.dart \
  -o build/owned-model-mutation-guard
build/owned-model-mutation-guard
```

Recompile after changing this rule, its shared model, SDK or dependency
configuration. Semantic resolution uses the selected Dart SDK (optional `--sdk
PATH`), the running Dart SDK for source execution, or the checkout's actual
`package_config.json` Flutter root for compiled/Flutter-host execution. A missing
or unsupported SDK is input exit 2; the binary's parent directory is never
assumed to be an SDK. Both entry points read the current owners and transport libraries;
there is no persisted source-result cache. Timing is informational in CI and
cannot change deterministic diagnostic/exit behavior. For the current three-owner
scope (1,147 authored owner lines), the justified local budgets are **25 seconds
source startup**, **30 seconds one-time compilation**, and **2.5 seconds compiled
feedback**. These are a separate semantic rule's budgets, not the smaller
parsed-AST aggregate's allowance. They include headroom above the measured cold
startup and median of three warm executions on the quiet Linux x86-64 checkout
with Dart 3.12.0 / analyzer 10.1.0. Resolution remains necessary for canonical
member identity; compiled feedback avoids the dominant source/JIT startup cost.

Repeat acceptance on the same host/SDK/configuration and scope, using both cold
startup and the median of three fresh warm processes. Compare input hashes before
and after; optimize a regression rather than silently raising the allowance.
There is no OS page-cache flush or persisted analysis-result cache. Raw SDK,
host, input hashes and measurements stay outside Git as required by
`docs/PERFORMANCE.md`.
