# ARCH_CURRENT_TOOL_EVENTS

Current vanilla Hermes tool activity uses `tool.start`, `tool.generating` and
`tool.complete`. Wing previously accepted legacy event names and top-level
identity/name/argument/status aliases in that event projection. The shipping
activity owner never passes saved history or resume maps through this parser.
Current saved tool rows and arbitrary nested tool results are separate contracts.

The independent parsed rule checks exactly four methods in three physical files:
`GatewayToolActivity.fromGatewayEvent`, `ChatRuntime.observeEvent`,
`ChatRuntime.observeTool`, and `ProfileWorkspaceController._event`. These
canonical classes/methods must exist in their exact physical containing libraries.
The controller genuinely uses parts: every declared part must exist, have one
reciprocal containing owner and an exact URI or named `part of` declaration.
The canonical path itself cannot be a part, and its class must be unique across
the validated library namespace. Missing, ambiguous, malformed, or mismatched
part ownership fails closed with `[ARCH_INPUT]`, exit 2.
The selector is the first method argument for the model/runtime seams, and the
second argument's `.type` for the coordinator seam. Parameter spelling may change.

Literal `tool.progress`, `tool.args_delta`, and `tool.error` dispatch comparisons
or switch patterns on those selectors produce the rule diagnostic, exit 1.
Direct literal top-level payload lookups or literal key lists supplied alongside
the model parser's second argument reject the retired aliases `toolCallId`,
`tool_call_id`, `id`, `tool`, `label`, `arguments`, `input`, `status`, `detail`,
`emoji`, and `error`. Simple preceding immutable aliases and parentheses retain
provenance. Nearer ordinary block variables and closure parameters shadow it. Loop/catch/
pattern declarations block attribution to an outer parameter.
Unrelated owners, methods and selectors remain valid. Nested results can contain
all those keys and event spellings, and `result_text` remains canonical.
Clean exit is 0; no migration baseline applies.

This is finite parsed literal dispatch/key syntax and ordinary local bindings.
It does not resolve Dart types, evaluate computed keys/event constants, traverse
helper calls, or model assignments, values of loop/catch/pattern bindings, cascades, or
interprocedural aliases. It does not establish every possible custom gateway
producer's behavior. Ordinary analysis and existing activity owner/matching/
visibility/disclosure controls complement it. Current stock emitter identity,
rather than a variable's `legacyStatus` label or absence of a metadata row, is the
source proof for the cleanup.

The exact upstream commit is `e1fdf003a668f97bf5a53d7675c1e70b1dcfec34`:

- `tool_progress.py`, blob `5e0f5be62c1804e92426bff8625399924481546f`, emits
  canonical start/complete envelopes; arbitrary tool errors remain inside `result`.
- `agent_callbacks.py`, blob `f9d97771cffdef37b38fe9246e6ffcb4e39f1a1c`, emits
  generating `{name}` and canonical child mirror start/complete envelopes.
- `connector_payload.py`, blob `37b90cf04035ff09df016443ddbffbf4e7ea84f4`, preserves
  dictionary keys while recursively redacting values.
- `hosted_room_member_activity.py`, blob `2de8f64af054dcae164679dfcffdb3401dea2e9c`,
  copies canonical outgoing payloads to a separate plugin hook.
- `contracts/events.py` declares the corresponding closed tool event models.

Twenty-seven detector fixtures exercise original dispatch/key violations, canonical
cases, immutable captures, renamed selector parameters, ordinary shadowing,
unrelated homonyms, arbitrary nested results, reciprocal URI/named parts, missing/mismatched part ownership, ambiguous owner
namespace, and invalid input. Three invoke the
actual CLI with expected 0/1/2 exits and diagnostic identity/location checks.
These fixtures and production checks still need Root's SDK execution; no elapsed
runtime, red/green result or CI acceptance is claimed by the private author.

```sh
dart run tools/architecture/rules/current_tool_events.dart --json
dart run tools/architecture/tests/current_tool_events_test.dart
flutter test --no-pub test/current_tool_events_guard_test.dart \
  test/gateway_activity_test.dart test/profile_execution_activity_test.dart \
  test/profile_activity_status_test.dart
```

Root must add this independent CLI to both existing quality/release gates and the
required-gate inventory, register the three new entry points in canonical roots,
and update discovery metadata. The shared Snapshot/Finding/CLI are reused.
