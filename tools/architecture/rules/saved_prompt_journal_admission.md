# ARCH_SAVED_PROMPT_JOURNAL_ADMISSION

A workspace can close while `_regenerate` or `editSavedPrompt` awaits its durable
pending-owner journal. The old sequence then staged reading history and accepted
a turn before rechecking the captured command owner. Both owner methods now call
`_commandOwner(chat)` immediately after the awaited journal and before those
local mutations. Controlled journal/close behavior cases protect the real refusal,
definitely-unsent settlement and retained reading outcomes.

This independent parsed rule follows the reciprocal URI part graph rooted at
`lib/core/services/profile_workspace_controller.dart`. Missing, duplicate,
nonreciprocal, named, nested and orphan parts fail input. It requires exactly one
canonical `ProfileWorkspaceController` class and one `ProfileChat` class, genuine
nonstatic ordinary `_journal` and `_commandOwner` members, and exactly one of each
canonical command method. Each command's first parameter must be the unprefixed,
nonnullable `ProfileChat chat`, without a shadowing class or method type parameter.
The canonical class may physically reside in a reciprocal part. No-write parts
and unrelated class, extension and top-level method homonyms remain valid.

For each command, one literal `chat.reading.stageRegeneration` or
`chat.reading.stageSavedPromptEdit` and one `chat._runtime.acceptTurn` must be direct
statements in the same block of that method, outside a nested function. The finite
accepted sequence in that block is: `await _journal();`, `_commandOwner(chat);`,
the stage call, then `acceptTurn()`. The last preceding direct awaited journal
must occupy that sequence. Explicit `this` on owner members and parentheses on
receivers are accepted. A missing/conditional/wrong-owner/wrong-chat fence, or
intervening work before staging or acceptance, produces a scoped finding.
Missing, duplicate, indirect or unsupported stage/accept/journal syntax fails
input rather than guessing that another operation establishes the same property.

Relevant enclosing parameters, direct block locals/local functions, catch and
loop bindings cannot masquerade as captured chat or canonical owner members.
Unrelated nested function homonyms are accepted. Pattern bindings of a relevant
name in an enclosing block/conditional/switch scope conservatively fail input;
this finite check does not resolve flow-dependent pattern promotion or aliases.
Explicit `this._commandOwner` remains a canonical member beside a local homonym.
Ordinary SDK analysis remains required for general semantic validity.

This protects a physical sequence, not `_commandOwner` implementation semantics,
transport dispatch, lifetime settlement or rollback. Aliased/transitive writers
and future alternative staging APIs are outside the finite property; replacing a
required literal stage yields unsupported input instead of a clean result. The
three real journal/close/refusal behavior cases provide the semantic evidence.
The existing canonical-state rule does not inspect these asynchronous commands,
and the native notification journal-ack rule protects a different boundary.

Clean input exits 0. Findings use `ARCH_SAVED_PROMPT_JOURNAL_ADMISSION`, physical
file/line and `ProfileWorkspaceController.<method>` subjects, then exit 1.
Unsupported scope/bindings/source exit 2 with `[ARCH_INPUT]`. No baseline exemption
is available. Thirty-four parsed fixtures cover both original missing fences,
repaired methods, nearby binding/indirection cases, physical part ownership and
actual CLI representatives for 1/0/2. CI invokes the independent production rule
and fixture host as mandatory hard-failing steps in both quality workflows.

```sh
dart run tools/architecture/rules/saved_prompt_journal_admission.dart --json
dart run tools/architecture/tests/saved_prompt_journal_admission_test.dart
flutter test --no-pub test/saved_prompt_journal_admission_guard_test.dart
```

The rule reuses Snapshot/Finding/CLI and introduces no dependencies or framework.
SDK execution and informational timing remain pending Root's validation lease.
