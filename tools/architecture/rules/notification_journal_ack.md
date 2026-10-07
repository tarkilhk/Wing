# Notification journal acknowledgment

`ARCH_NOTIFICATION_JOURNAL_ACK` protects the canonical
`ChatNotificationCoordinator` class in
`lib/core/services/chat_notification_coordinator.dart` and its actual parts.
A real SharedPreferences mutator returns `Future<bool>`: completing the future
alone does not confirm the write. The original `Future<void> _write() =>
preferences.setString(...)` discarded that acknowledgment.

The finite property rejects such a result in a bare or awaited expression
statement, or a direct arrow/return whose actual callable returns `void` or
`Future<void>`. Parentheses, await and erased casts retain the underlying result.
Direct cascade mutator sections discard their result even when the cascade's
receiver is retained or returned; those sections are checked independently.
Resolved method/declaration identity establishes canonical `setBool`, `setInt`,
`setDouble`, `setString`, `setStringList`, `remove` and `clear`; spelling alone
never produces a finding. Prefixes, typedefs, receiver aliases, barrels, actual
parts, statically initialized local/field/top-level tearoff or future-value
aliases and expression-bodied getter aliases are covered. Mutable aliases are
unsupported INPUT2 when their actual target cannot be established. Local homonyms and
storing, checking or returning the typed bool/future remain supported.

Parsed discard shapes and a conservative alias vocabulary select candidates.
Candidate roots mirror the resolved origin walk's supported expression shapes;
names inside arguments or closures never impersonate the outer call. Nested
discard statements/arrows/returns are still visited independently. Qualified
member access uses field/top-level/getter aliases; unrelated local aliases cannot
be accessed as an object's member. Bare aliases retain the complete vocabulary.
The parsed clean path excludes direct `clear`/`remove` calls on a final private
field initialized by a language map/set literal when that field is the sole
matching binding in its entire actual library. A competing local, formal, catch,
pattern, getter, field or constructor initializer keeps semantic resolution.
Private identity and complete library binding collection prevent same-library
getter overrides and lexical shadows from impersonating the literal receiver.
Only direct bare/`this` receivers and direct cascade sections qualify; mutable
references, aliases, compound receivers and inherited members remain semantic.
Literal contents can change without replacing that final collection reference.
This does not infer types or exempt a spelling such as `Map`; an invalid contextual
annotation remains mandatory SDK-owned, with an actual dual fixture proof.
Namespace/part ownership, actual package/file URI origins and configured SDK
SourceFactory mappings are checked before filtering. A physically existing parent
file cannot satisfy an unresolved package-relative namespace.
Forward `part` and reciprocal URI `part of` mappings must both resolve from their
actual source origins to the parsed containing library.
Conditional authored namespaces and unowned/out-of-scope parts return INPUT2. Candidate resolution
errors or dynamic/unknown mutation receivers return INPUT2. Ordinary semantic
errors with no candidate remain the mandatory SDK analyzer's responsibility;
fixtures prove a clean rule result and the actual SDK's rejection. Standard
analyzer summary caching uses the existing shared helper, with no verdict cache.

This does **not** prove correct settlement: merely storing a bool is accepted.
Arbitrary wrappers, block getter/function result inference, mutable reassignment,
interprocedural callback behavior and deliberate non-void type erasure are outside
this finite property. It does not prove restoration, retry, stable policy
acknowledgment, absence of ABA, permission admission or journal/readback durability.
The notification preference refresh and race behavioral regressions remain
necessary; static detection cannot establish their event order.

Run independently:

```sh
dart run tools/architecture/rules/notification_journal_ack.dart --root . --json
dart run tools/architecture/tests/notification_journal_ack_test.dart
dart compile exe tools/architecture/rules/notification_journal_ack.dart -o build/notification-journal-ack
dart run tools/architecture/tests/notification_journal_ack_test.dart --compiled build/notification-journal-ack
```

Actual CLI exit codes are 0 clean, 1 with stable rule/file/line findings, and 2
invalid input. `--sdk PATH` supplies validated SDK provenance. The host wrapper
runs both fixture proof and an actual production scan through the validated Dart
SDK; it never assumes Flutter's executable is Dart. Fixture scratch directories
remain alive until the supervised child VM terminates. Shared summary writes
finish before returning and cannot outlive context disposal. Root owns mandatory CI/census integration and feedback budgets;
first-use and warm-cache timings must be recorded separately on immutable inputs.
