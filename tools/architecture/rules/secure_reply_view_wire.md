# Secure reply view codec dependency

`ARCH_SECURE_REPLY_VIEW_WIRE` protects only the canonical
`GatewaySensitivePromptPanel` library at
`lib/core/widgets/gateway_sensitive_prompt_panel.dart`. The actual original view
imported `dart:convert` and constructed secure reply JSON; the successor delegates
normalization and encoding to `GatewaySensitivePromptRequest`.

The finite parsed rule forbids a declared dependency on `dart:convert` through a
view import or export, including local/package barrels, conditional exports,
prefixes and show/hide filters. This deliberately protects the namespace
dependency itself: combinators do not authorize retaining a codec dependency.
Imports inside an owner stay private and are accepted; only its exports propagate
the dependency. Unrelated views may import codecs. Export cycles terminate with
visited paths. Package roots come from the ordinary package configuration.

The canonical class may reside in an actual URI or named part of this library.
Missing/ambiguous panel authority, malformed namespaces, missing imported/exported
files, detached imported parts and invalid actual part ownership return input 2.
There is no whole-checkout scan, semantic framework or result cache. The existing
`checkViewAdapterDependencies` helper remains unchanged because it treats external
namespaces as terminal and cannot protect `dart:convert` through a barrel.

```sh
dart run tools/architecture/rules/secure_reply_view_wire.dart
dart run tools/architecture/tests/secure_reply_view_wire_test.dart
flutter test test/secure_reply_view_wire_guard_test.dart
```

The standalone CLI accepts optional `--root PATH`: exit 0 passes the finite
contract, exit 1 reports a violation and exit 2 reports invalid/unsupported input.
Fixtures prove direct/prefix/show/hide dependencies, local/package/conditional
barrels, export cycles, legitimate owner codecs and unrelated views, actual
parts, missing authority and source CLI exits 0/1/2.

For original-production red proof, copy the original panel from
`/tmp/wing-secure-reply-original-freeze` into an isolated successor checkout and
run this exact rule CLI with `--root` pointing there. The original `dart:convert`
import must produce this diagnostic at its actual line. Restore the successor
panel from `/tmp/wing-secure-reply-formatted-source-freeze` and require exit 0.
No SDK, formatting or test jobs were run by the source author. Integration owns
those checks, CI registration and measured feedback budgets.

The retirement rule separately protects `_canSubmit`, `_normalizedCode` and
`_responseValue`. This namespace guard does not prove encoding behavior, async
ordering or secret-value lifetime; model and panel behavioral tests own those
properties. Standard Dart/Flutter analysis validates language/import correctness.
