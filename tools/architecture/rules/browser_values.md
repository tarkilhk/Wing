# ARCH_BROWSER_VALUES

Canonical published browser values in `lib/core/models/chat_list_view.dart` must be sealed final scalar/typed facts. The original `ChatListEntry.row` and project fields exported mutable raw maps; the original group entries list could be mutated by a caller. `ChatListEntry` and `ChatListGroup` are checked first so original raw maps fail with exit 1. Other adopted value declarations must then exist unambiguously (input exit 2).

The finite allowed field types belong to these seven exact classes. Four collection constructors must use their explicit `List.unmodifiable`, `Set.unmodifiable` or `Map.unmodifiable` capture. Raw map admission parameters, owner-private reconciliation, unrelated classes and other libraries remain valid. This is a finite declared-value/construction contract, not a general type resolver or proof of arbitrary semantic immutability, future getter dataflow, protocol decoding or runtime ownership.

Run `dart run tools/architecture/rules/browser_values.dart --root . --roles tools/architecture/roles.json --json`. Fixtures: `dart run tools/architecture/tests/browser_values_test.dart`. Exit 0 accepts, 1 reports the value violation, 2 rejects unsupported/missing input. Root owns CI integration and the focused original/current proof; no job has been claimed by the source author.
