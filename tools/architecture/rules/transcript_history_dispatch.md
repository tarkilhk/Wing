# ARCH_TRANSCRIPT_HISTORY_DISPATCH

The actual older-history regression dispatched `widget.onLoadOlder()` directly
from the transcript's ScrollNotification handler. The owner immediately published
history-loading state while Flutter was delivering layout-time scroll metrics,
causing a notifier during layout. The repaired `_scheduleLoadOlder` coalesces
scroll offers, registers one post-frame callback, and rechecks the captured chat,
mount and current scroll/loading conditions before dispatch. Existing explicit
Load older/Retry older button callbacks remain direct user intents and must work
at scroll offset zero.

This independent parsed rule inspects `_ProfileTranscriptState` in the exact
`lib/core/screens/profile_transcript.dart` library. Every method invocation named
`onLoadOlder` on the spelled `widget` receiver (including parentheses or
`this.widget`) must have one of two closest function-expression ancestors:

- The first inline argument of the spelled
  `WidgetsBinding.instance.addPostFrameCallback` registration.
- An inline function supplied as the named `onPressed` argument of a parsed call.

An arbitrary closure, the original `onNotification` callback, or a newly named
helper making a direct invocation fails. A nested helper does not inherit its
outer callback's exemption. Other receivers are outside this literal boundary.
The rule scans all members of the canonical state, so renaming the scheduling
helper does not exempt a direct physical call. It does not impose a scroll
threshold on button intent or edit the buttons.

This is finite parsed receiver/member/callback syntax, not resolved SDK or button
type provenance, alias/tear-off/interprocedural analysis, or proof of callback
timing. Captured-chat checks, request coalescing, actual mounted authority,
threshold behavior, errors and later publication require the existing focused
history/scroll/runtime behavior checks. In particular, passing the rule does not
prove that a closure is invoked by the real Flutter scheduler if SDK names are
shadowed. Ordinary analysis and behavioral controls remain required.

Unsafe invocations produce `ARCH_TRANSCRIPT_HISTORY_DISPATCH` with physical file,
line and canonical receiver subject, then exit 1. Clean exit is 0. A missing or
ambiguous canonical state, unsupported part scope or invalid Snapshot/source
input fails with CLI `[ARCH_INPUT]` and exit 2. There is no migration exemption.
Fifteen small detector fixtures cover the encountered direct call, repaired
coalesced/captured frame closure, direct button intent, helper/closure regressions,
receiver scope, and invalid input. Three invoke actual CLI exits 1/0/2.

```sh
dart run tools/architecture/rules/transcript_history_dispatch.dart --json
dart run tools/architecture/tests/transcript_history_dispatch_test.dart
flutter test --no-pub test/transcript_history_dispatch_guard_test.dart
```

The rule reuses the existing Snapshot, Finding and CLI implementation.
