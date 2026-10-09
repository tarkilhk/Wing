# ARCH_RECENT_CAPTURE_RELEASE_SAFE

Signed Android acceptance found that Recents' `_capture` read Flutter's
`RenderObject.debugNeedsPaint` during normal interaction. That getter initializes
its return value only inside an assertion. Release builds remove the assertion,
so both runtime reads threw `LateInitializationError` even though the debug
emulator journeys and host tests passed.

The capture now awaits the framework's completed frame before taking a raster
snapshot. It retains the existing mounted, generation, chat identity and boundary
attachment checks and bounded image ownership. A queued red-to-green chat rebuild
regression checks actual captured pixels and fails against the old conditional
paint wait.

This independent guard resolves references in the canonical
`lib/core/widgets/recent_conversations/recent_conversation_switcher.dart` library.
Reads of the actual Flutter `RenderObject.debugNeedsPaint` getter must be inside
an assertion. Resolution distinguishes imported or aliased framework members from
unrelated getters with the same spelling. Assertion-only reads and the repaired
frame wait are valid; runtime reads emit `ARCH_RECENT_CAPTURE_RELEASE_SAFE` and
fail. There is no compatibility exemption.

The rule deliberately covers this canonical capture library and this encountered
SDK getter. It does not prove frame ordering, image pixels, gesture behavior or
the runtime safety of other debug APIs. Those properties need their corresponding
behavioral or device checks. Its assertion exemption is a lexical boundary, not
interprocedural proof that a retained closure can never escape.

The rule is registered in `check_all.dart`, so the staged source hook and CI run
it. Resolved valid/invalid fixtures and command-line failure controls live in
`test/recent_capture_release_safe_guard_test.dart`.

```sh
dart run tools/architecture/rules/recent_capture_release_safe.dart
flutter test --no-pub test/recent_capture_release_safe_guard_test.dart
flutter test --no-pub test/recent_conversation_switcher_test.dart
```

Signed-release acceptance must exercise Choose recent conversation and the
previous/next actions. A debug-only run cannot close an assertions-disabled
runtime finding.
