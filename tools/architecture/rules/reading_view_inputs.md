# ARCH_READING_VIEW_INPUT

Four canonical reading declarations retain typed, non-null captured inputs:

| Canonical library under `lib/core/` | Declared input |
| --- | --- |
| `widgets/profile_message.dart` | `ProfileMessage.message`: final `TranscriptMessage` |
| `widgets/profile_tool_activity.dart` | `ProfileToolActivity.results`: final `List<TranscriptToolResult>` |
| `screens/profile_transcript.dart` | `ProfileTranscript.timeline`: final `TranscriptTimeline` |
| `widgets/profile_tool_activity.dart` | `ProfileToolActivitySection.section`: final `TranscriptTimelineSection` |

Message and tool types must come directly from the canonical
`lib/core/models/transcript_message.dart` import; timeline and section types from
`lib/core/models/transcript_timeline.dart`. Ordinary and prefixed imports,
relative/package:wing normalized paths and show/hide visibility are checked.
A same-spelling local class/alias/type parameter or explicit direct local import
cannot masquerade as that projection. Unrelated classes and their raw inputs
remain valid, including unrelated timeline/section fields in the same library.
The result list itself and its element type must both be non-null.
`dynamic`, `Object`, raw `Map`, nullable or missing type arguments, writable
fields and uninitialized late-final input slots fail this declaration contract.

This small independent rule uses the existing parsed Snapshot and CLI. Missing
or ambiguous canonical classes/fields, static/getter substitutes, malformed
sources, actual parts or conditional view namespaces return input exit 2. The
current finite declaration contract requires a direct canonical model import;
visible local barrels/parts fail input 2, and alias spellings do not certify it.
The transcript uses an explicit canonical timeline prefix: unrelated unprefixed
controller imports with parts cannot participate in that field's namespace.
Implicit/direct `dart:core` List binding and direct local List homonyms are checked; standard Dart analysis remains
responsible for language bodies and SDK `List` binding. No namespace resolver,
framework, cache or symbol-dataflow engine is added.

```sh
dart run tools/architecture/rules/reading_view_inputs.dart --json
dart run tools/architecture/tests/reading_view_inputs_test.dart
```

Twelve focused detector cases run in process. Raw-wire original leaf inputs,
nullable/Object/dynamic widening and a same-spelling local fake fail; typed
inputs with unrelated homonyms and a prefixed normalized canonical import pass.
Raw timeline/section inputs, nullable/dynamic widening and same-spelling local
timeline/section fakes fail; the typed prefixed fixture covers both model paths.
That fixture also accepts the transcript's unrelated imported runtime library
with actual parts without expanding the namespace checker.
Missing completed input and unsupported part scope fail closed. Three source
CLI representatives check exits 1/0/2 and exact diagnostic identity/location.
Root owns required CI registration and executed proof; this source handoff
contains no SDK jobs, runtime result or performance claim.

This protects declared typed reading inputs. It does not prove nested defensive
copying, classify transcript content, enforce deep immutability of arbitrary
models, inspect callbacks, establish section ordering or verify viewport geometry.
`ARCH_DOMAIN_DEPENDENCY` keeps the projection's domain imports pure; retained
message/attachment tests check projection behavior and copies. The existing
`ARCH_RETIRED_DECLARATION` separately bans the removed `ProfileToolActivity.messages`
input, removed widget grouping/reasoning/eligibility APIs and the exact removed
tool route/provider/model policy APIs. Missing successor timeline/section fields
in the original widget declarations produce input exit 2; original policy removal
is proved separately by the exact retirement rule, not claimed as this rule's
exit-1 counterexample. This rule's explicit raw-field fixtures establish exit 1.
It does not ban moved `AdminVoicePage` or the retained presentation `_setup` wrapper.


The same canonical reading boundary also rejects the observed copied pending-input
union inside `_ProfileTranscriptState` in `profile_transcript.dart`. Three `!= null`
checks for `approval`, `pendingQuestion` and `secureInput`, joined by `||` on the
same literal `widget.chat.runtime` receiver or a final block-local capture of
`widget.chat`, must read the existing `runtime.needsInput` observation instead.
Parentheses, reordered operands, reversed null comparisons and a renamed local
capture are covered. Individual request-specific rendering checks, unrelated
classes/receivers, method parameters, closure parameters and nearer unrelated
local shadows remain valid, including a literal `widget` parameter shadow. Loop declarations, loop patterns,
catch bindings and local/if/switch patterns also prevent an outer capture from
being mistaken for a nearer receiver. Diagnostic subject: `ProfileTranscript.needsInput`.

This is finite AST copied-union prevention, not resolved receiver or arbitrary
business/dataflow proof. Further aliases, helper calls, computed dispatch,
renamed state classes, different logical encodings are not established by this check. The canonical getter itself remains owned by
`ChatRuntimeObservation`; the guard does not freeze its classification or mandate
request kinds. Runtime correlation and completed-plus-pending-input behavior use
existing workspace/runtime tests. Transcript input-navigation tests retain
viewport, jump-label, action and mounted form identity assertions.

Twenty additional finite fixtures include both invalid union spellings and nearby
valid rendering/homonym/shadow cases. The copied-union fixture runs the existing
independent source CLI as another exit-1 representative; existing exit-0/2 and
exact finding identity/location checks remain. The 32 finite fixtures and four CLI representatives exercise invalid/valid/input
exits and exact finding identity/location. Original production has two copied
union findings; repaired production reads the canonical observation. Existing
required reading-view CLI/fixture CI registration covers the extended rule.
